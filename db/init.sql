CREATE TABLE IF NOT EXISTS reservations (
  id SERIAL PRIMARY KEY,
  full_name VARCHAR(150) NOT NULL,
  student_index VARCHAR(50) NOT NULL,
  room_number VARCHAR(20) NOT NULL,
  computer_number VARCHAR(50) NOT NULL,
  purpose TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_reservations_student_index
  ON reservations(student_index);

CREATE INDEX IF NOT EXISTS idx_reservations_room_number
  ON reservations(room_number);

CREATE INDEX IF NOT EXISTS idx_reservations_purpose
  ON reservations(purpose);