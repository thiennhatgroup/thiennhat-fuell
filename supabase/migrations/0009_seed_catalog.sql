-- ============================================================================
-- 0009_seed_catalog.sql — Seed danh mục nền từ sheet cũ
-- (DANH_MUC / _TON_CAPACITY / _DM_BOM_BOM của File nhap lieu xang dau_v11.xlsx).
-- Idempotent: on conflict (normalize_text(...)) do nothing → chạy lại an toàn,
-- KHÔNG đè chỉnh sửa của Kế toán. Xe biển số chuẩn = có công-tơ-mét; thiết bị/
-- công trình = không công-tơ-mét (Kế toán chỉnh lại ở màn Danh mục & Xe nếu cần).
-- Téc chưa gán loại dầu (oil_type_id null) — Kế toán gán sau ở UI.
-- ============================================================================

insert into oil_types (name) values
  ('DO 0.05S'),
  ('DO'),
  ('Dầu động cơ'),
  ('Dầu thủy lực'),
  ('Dầu cầu'),
  ('Dầu số')
on conflict (normalize_text(name)) do nothing;

insert into suppliers (name) values
  ('Cty CP TMDV Hồng Quân (dầu)'),
  ('Công ty TNHH Xây Dựng và Cơ Khí Xuân Cương'),
  ('Hải Tân'),
  ('Cây 25'),
  ('Cây 25 TP'),
  ('Hồng Quân'),
  ('Xuân Cương'),
  ('NCC khác'),
  ('Quang Cường'),
  ('Thủ Đô')
on conflict (normalize_text(name)) do nothing;

insert into tanks (name, capacity_liters) values
  ('Téc 1', 15000),
  ('Téc 2', 31000),
  ('Téc 3', 31000),
  ('Téc cát nghiền', 31000)
on conflict (normalize_text(name)) do nothing;

insert into vehicles (plate, pump_norm, has_odometer) values
  ('19H09482', 7.0, true),
  ('28A30696', 0, true),
  ('28C00462', 7.0, true),
  ('28C01165', 0, true),
  ('28C01406', 0, true),
  ('28C01544', 0, true),
  ('28C01622', 0, true),
  ('28C01647', 0, true),
  ('28C01731', 0, true),
  ('28C01743', 0, true),
  ('28C02106', 0, true),
  ('28C02410', 0, true),
  ('28C02545', 0, true),
  ('28C02574', 0, true),
  ('28C02770', 5.0, true),
  ('28C02973', 0, true),
  ('28C02986', 0, true),
  ('28C03044', 0, true),
  ('28C03261', 0, true),
  ('28C03323', 0, true),
  ('28C03385', 0, true),
  ('28C03652', 0, true),
  ('28C03695', 0, true),
  ('28C03927', 0, true),
  ('28C04509', 0, true),
  ('28C04536', 0, true),
  ('28C04576', 0, true),
  ('28C05090', 0, true),
  ('28C05345', 0, true),
  ('28C05661', 0, true),
  ('28C05739', 0, true),
  ('28C06369', 0, true),
  ('28C06447', 0, true),
  ('28H00003', 0, true),
  ('28H00061', 0, true),
  ('28H00354', 0, true),
  ('28H00603', 0, true),
  ('28H00609', 0, true),
  ('28H00669', 10.0, true),
  ('28H00680', 10.0, true),
  ('28H01070', 10.0, true),
  ('28H01364', 10.0, true),
  ('29E17269', 0, true),
  ('29E17273', 0, true),
  ('29E17410', 0, true),
  ('29E17417', 0, true),
  ('29E17539', 0, true),
  ('29E18160', 0, true),
  ('Cát nghiền', 0, false),
  ('Công trình apphan', 0, false),
  ('Công trình asphalt', 0, false),
  ('Ctr apphan', 0, false),
  ('LG53F', 0, false),
  ('Máy lu lốp', 0, false),
  ('Máy phát điện', 0, false),
  ('Máy rải thảm', 0, false),
  ('Xe 600148', 0, false),
  ('Xe ben mới', 0, false),
  ('Xúc Đào', 0, false),
  ('Xúclật asphalt', 0, false),
  ('Xúclật855H', 0, false),
  ('Xúclật855N', 0, false)
on conflict (normalize_text(plate)) do nothing;

