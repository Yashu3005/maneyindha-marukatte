# GitHub Workflow

## Branches

```
main      → production (protected, PR + review + green CI required)
develop   → integration
feature/* → new work        e.g. feature/customer-auth
bugfix/*  → fixes           e.g. bugfix/cart-total
```

## Flow

feature branch → PR to develop → CI (lint + tests + build) → review → merge
→ release PR develop→main → Vercel production deploy.

## Commit convention (Conventional Commits)

```
feat: add customer authentication
fix: resolve cart calculation issue
docs: update deployment guide
test: add order API tests
chore: bump dependencies
```

## Branch protection (set in repo settings)

- `main`: require PR, 1 review, CI passing, no force push
- `develop`: require CI passing
