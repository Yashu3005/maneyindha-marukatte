const { v2: cloudinary } = require('cloudinary');
const AppError = require('../utils/AppError');
const logger = require('../utils/logger');
const Business = require('../models/Business');
const { sniff: sniffImage } = require('./avatar.service');

const MAX_BYTES = 5 * 1024 * 1024;
const DOC_TYPES = ['id_proof', 'business_proof', 'address_proof', 'other'];
const REQUIRED_TYPES = ['id_proof', 'business_proof'];
const IDENTITY_TYPES = ['Aadhaar', 'Voter ID', 'Driving License', 'Passport'];
const LINK_TTL_SECONDS = 5 * 60;
const EDITABLE = ['pending', 'rejected'];

const configured = () => !!(process.env.CLOUDINARY_CLOUD_NAME && process.env.CLOUDINARY_API_KEY && process.env.CLOUDINARY_API_SECRET);
const configure = () => cloudinary.config({
  cloud_name: process.env.CLOUDINARY_CLOUD_NAME, api_key: process.env.CLOUDINARY_API_KEY,
  api_secret: process.env.CLOUDINARY_API_SECRET, secure: true,
});

// The type comes from the file's own bytes. The declared name / mimetype is not trusted.
function sniff(buf) {
  const img = sniffImage(buf);
  if (img) return { mime: img, ext: img === 'image/jpeg' ? 'jpg' : img === 'image/png' ? 'png' : 'webp', kind: 'image' };
  if (buf.length >= 5 && buf.subarray(0, 5).toString('latin1') === '%PDF-') return { mime: 'application/pdf', ext: 'pdf', kind: 'raw' };
  return null;
}

// Test seam: replaced by stand-ins in tests.
const provider = {
  upload(buffer, { publicId, kind }) {
    configure();
    return new Promise((resolve, reject) => {
      const stream = cloudinary.uploader.upload_stream(
        // `authenticated` = not reachable by URL without a signature; nothing public is created.
        { folder: 'verification', public_id: publicId, type: 'authenticated', resource_type: kind, overwrite: true, invalidate: true },
        (err, result) => (err ? reject(err) : resolve(result))
      );
      stream.end(buffer);
    });
  },
  destroy(doc) {
    configure();
    return cloudinary.uploader.destroy(doc.publicId, { type: 'authenticated', resource_type: doc.resourceType || 'image', invalidate: true });
  },
  signedUrl(doc) {
    configure();
    return cloudinary.utils.private_download_url(doc.publicId, doc.format || '', {
      type: 'authenticated', resource_type: doc.resourceType || 'image',
      expires_at: Math.floor(Date.now() / 1000) + LINK_TTL_SECONDS,
    });
  },
};

const safeName = (n) => String(n || 'document').replace(/[^\w.\- ]+/g, '_').slice(0, 80);

// What the owner may see about their own documents: no storage ids.
const describe = (d) => ({
  id: String(d._id), type: d.type, identityType: d.identityType, mime: d.mime, bytes: d.bytes,
  name: d.originalName, uploadedAt: d.uploadedAt,
});

async function ownBusiness(ownerId, businessId) {
  const business = await Business.findOne({ _id: businessId, owner: ownerId });
  if (!business) throw new AppError('Business not found', 404);
  return business;
}

async function addDocument(ownerId, businessId, file, { type, identityType } = {}) {
  if (!DOC_TYPES.includes(type)) throw new AppError('Choose which document this is', 422);
  if (type === 'id_proof' && !IDENTITY_TYPES.includes(identityType)) throw new AppError('Choose the identity type', 422);
  if (!file?.buffer?.length) throw new AppError('Choose a file to upload', 422);
  if (file.buffer.length > MAX_BYTES) throw new AppError('File must be 5 MB or smaller', 413);
  const kind = sniff(file.buffer);
  if (!kind) throw new AppError('Only PDF, JPEG, PNG or WebP files are allowed', 415);
  if (!configured()) throw new AppError('Document upload is not available right now', 503, 'UPLOAD_NOT_CONFIGURED');

  const business = await ownBusiness(ownerId, businessId);
  if (!EDITABLE.includes(business.verification.status)) {
    throw new AppError(`Documents cannot be changed while the application is ${business.verification.status.replace('_', ' ')}`, 422);
  }

  // Unguessable id, one document per type: a re-upload replaces the previous one.
  const publicId = `${businessId}_${type}_${Date.now().toString(36)}`;
  let result;
  try {
    result = await provider.upload(file.buffer, { publicId, kind: kind.kind });
  } catch (e) {
    logger.error(`Verification document upload failed: ${e?.http_code || ''} ${e?.message || 'unknown'}`);
    throw new AppError('Could not upload the document. Please try again.', 502, 'UPLOAD_FAILED');
  }
  if (!result?.public_id) throw new AppError('Could not upload the document. Please try again.', 502, 'UPLOAD_FAILED');

  const previous = business.verification.documents.filter((d) => d.type === type);
  business.verification.documents = business.verification.documents.filter((d) => d.type !== type);
  business.verification.documents.push({
    type, identityType: type === 'id_proof' ? identityType : undefined,
    publicId: result.public_id, resourceType: kind.kind, format: kind.ext, mime: kind.mime,
    bytes: file.buffer.length, originalName: safeName(file.originalname), uploadedAt: new Date(),
  });
  await business.save();
  // Best effort: the new document is already recorded even if the old remote file can't be removed.
  for (const old of previous) {
    if (old.publicId) await provider.destroy(old).catch((e) => logger.warn(`Old document delete failed: ${e?.message}`));
  }
  return business.verification.documents.map(describe);
}

async function listDocuments(ownerId, businessId) {
  const business = await ownBusiness(ownerId, businessId);
  return { status: business.verification.status, photoUrl: business.bannerUrl || null, documents: business.verification.documents.map(describe) };
}

async function removeDocument(ownerId, businessId, docId) {
  const business = await ownBusiness(ownerId, businessId);
  if (!EDITABLE.includes(business.verification.status)) {
    throw new AppError('Documents cannot be changed while the application is under review', 422);
  }
  const doc = business.verification.documents.id(docId);
  if (!doc) throw new AppError('Document not found', 404);
  const copy = { publicId: doc.publicId, resourceType: doc.resourceType };
  doc.deleteOne();
  await business.save();
  if (copy.publicId && configured()) await provider.destroy(copy).catch((e) => logger.warn(`Document delete failed: ${e?.message}`));
  return business.verification.documents.map(describe);
}

// Moves the application to review, only when the required documents were really uploaded.
async function submitForReview(ownerId, businessId) {
  const business = await ownBusiness(ownerId, businessId);
  if (!EDITABLE.includes(business.verification.status)) {
    throw new AppError(`Application is already ${business.verification.status.replace('_', ' ')}`, 422);
  }
  const have = new Set(business.verification.documents.filter((d) => d.publicId).map((d) => d.type));
  const missing = REQUIRED_TYPES.filter((t) => !have.has(t));
  if (missing.length) {
    throw new AppError(`Upload your ${missing.map((t) => (t === 'id_proof' ? 'ID proof' : 'business proof')).join(' and ')} first`, 422, 'DOCUMENTS_MISSING');
  }
  if (!/^https:\/\//.test(business.bannerUrl || '')) {
    throw new AppError('Add a profile photo of your business first', 422, 'PHOTO_MISSING');
  }
  business.verification.status = 'in_review';
  business.verification.rejectionReason = undefined;
  await business.save();
  return business;
}

// Admin only: a short-lived link to one document.
async function adminDocumentLink(businessId, docId) {
  const business = await Business.findById(businessId);
  const doc = business?.verification?.documents?.id(docId);
  if (!doc || !doc.publicId) throw new AppError('Document not found', 404);
  if (!configured()) throw new AppError('Document storage is not available right now', 503, 'UPLOAD_NOT_CONFIGURED');
  return { url: provider.signedUrl(doc), expiresInSeconds: LINK_TTL_SECONDS, mime: doc.mime, type: doc.type };
}

module.exports = {
  addDocument, listDocuments, removeDocument, submitForReview, adminDocumentLink,
  sniff, MAX_BYTES, DOC_TYPES, IDENTITY_TYPES, _provider: provider,
};
