# Database migrations

No production schema is defined yet. First approve the ERD and tenant model, then add timestamped SQL migrations.

Required: company_id scoping, RLS policies, least-privilege roles, atomic financial posting, audit logging, indexes, and staging verification. Never commit service-role keys.
