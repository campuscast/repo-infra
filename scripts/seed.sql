-- Seed data for local development
-- Run against each service DB

-- === auth_db ===
\c auth_db;

INSERT INTO roles (id, name, permissions) VALUES
  ('00000000-0000-0000-0000-000000000001', 'admin', 'schedule:write,content:upload,device:manage,zone:manage,audit:read'),
  ('00000000-0000-0000-0000-000000000002', 'editor', 'schedule:write,content:upload')
ON CONFLICT DO NOTHING;

-- password: 'admin123' (bcrypt hash)
INSERT INTO users (id, email, password_hash, mfa_enabled) VALUES
  ('00000000-0000-0000-0000-000000000010', 'admin@campuscast.local', '$2b$10$abcdefghijklmnopqrstuuABCDEFGHIJKLMNOPQRSTUVWXYZ012', false),
  ('00000000-0000-0000-0000-000000000011', 'editor@campuscast.local', '$2b$10$abcdefghijklmnopqrstuuABCDEFGHIJKLMNOPQRSTUVWXYZ012', false)
ON CONFLICT DO NOTHING;

INSERT INTO user_roles ("usersId", "rolesId") VALUES
  ('00000000-0000-0000-0000-000000000010', '00000000-0000-0000-0000-000000000001'),
  ('00000000-0000-0000-0000-000000000011', '00000000-0000-0000-0000-000000000002')
ON CONFLICT DO NOTHING;

-- === zone_policy_db ===
\c zone_policy_db;

INSERT INTO zones (zone_id, name, description) VALUES
  ('00000000-0000-0000-0000-000000000100', 'Main Campus', 'Primary campus zone')
ON CONFLICT DO NOTHING;

INSERT INTO screen_groups (group_id, zone_id, name) VALUES
  ('00000000-0000-0000-0000-000000000200', '00000000-0000-0000-0000-000000000100', 'Lobby Screens')
ON CONFLICT DO NOTHING;

INSERT INTO zone_policies (id, zone_id, max_schedule_slots, max_content_size_mb, crdt_enabled, max_ops_per_minute, max_batch_size) VALUES
  ('00000000-0000-0000-0000-000000000300', '00000000-0000-0000-0000-000000000100', 100, 500, false, 60, 50)
ON CONFLICT DO NOTHING;

-- === device_db ===
\c device_db;

INSERT INTO devices (device_id, device_name, device_type, zone_id, group_id, status, mqtt_client_id) VALUES
  ('00000000-0000-0000-0000-000000000400', 'Lobby TV 1', 'android_tv', '00000000-0000-0000-0000-000000000100', '00000000-0000-0000-0000-000000000200', 'active', 'dev-lobby1')
ON CONFLICT DO NOTHING;

-- Zone assignment for users
\c auth_db;
INSERT INTO user_zone_assignments (id, user_id, zone_id, role) VALUES
  ('00000000-0000-0000-0000-000000000500', '00000000-0000-0000-0000-000000000010', '00000000-0000-0000-0000-000000000100', 'admin'),
  ('00000000-0000-0000-0000-000000000501', '00000000-0000-0000-0000-000000000011', '00000000-0000-0000-0000-000000000100', 'editor')
ON CONFLICT DO NOTHING;
