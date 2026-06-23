import pg from "pg";

const { Pool } = pg;

export const pool = new Pool({
  host: process.env.DB_HOST || "localhost",
  port: Number(process.env.DB_PORT || 5432),
  user: process.env.DB_USER || "student",
  password: process.env.DB_PASSWORD || "student",
  database: process.env.DB_NAME || "reservations",
  max: 10,
  idleTimeoutMillis: 30000,
  connectionTimeoutMillis: 5000
});

export async function checkDatabase() {
  const result = await pool.query("SELECT NOW() AS current_time");
  return result.rows[0];
}
