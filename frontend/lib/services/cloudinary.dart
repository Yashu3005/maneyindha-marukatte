import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';

const _cloudName = 'nykyckqh';
const _uploadPreset = 'maneindha';

/// Opens the device/file picker and uploads the chosen image to Cloudinary
/// (unsigned preset). Returns the hosted URL, or null if cancelled.
Future<String?> pickAndUploadImage() async {
  final result = await FilePicker.platform.pickFiles(
    type: FileType.image,
    withData: true,
  );
  final file = result?.files.single;
  if (file == null || file.bytes == null) return null;

  final form = FormData.fromMap({
    'file': MultipartFile.fromBytes(file.bytes!, filename: file.name),
    'upload_preset': _uploadPreset,
  });
  final res = await Dio().post(
    'https://api.cloudinary.com/v1_1/$_cloudName/image/upload',
    data: form,
  );
  return res.data['secure_url'] as String?;
}
