import "dotenv/config";
import cors from "cors";
import express from "express";
import { checkDatabase, pool } from "./db.js";

const app = express();
const PORT = Number(process.env.PORT || 5000);

app.use(cors());
app.use(express.json());

app.get("/health", async (_req, res) => {
  try {
    const database = await checkDatabase();
    res.json({
      success: true,
      status: "running",
      service: "equipment-reservation-backend",
      database: "available",
      databaseTime: database.current_time,
      timestamp: new Date().toISOString()
    });
  } catch (error) {
    res.status(503).json({
      success: false,
      status: "running",
      service: "equipment-reservation-backend",
      database: "unavailable",
      error: error.message,
      timestamp: new Date().toISOString()
    });
  }
});

app.get("/reservations", async (_req, res) => {
  try {
    const result = await pool.query(`
      SELECT
        id,
        full_name,
        student_index,
        room_number,
        computer_number,
        purpose,
        created_at
      FROM reservations
      ORDER BY created_at DESC, id DESC
    `);

    return res.json({
      success: true,
      reservations: result.rows
    });
  } catch (error) {
    console.error("Reservation loading failed:", error);

    return res.status(500).json({
      success: false,
      error: "Rezervacije nije moguće učitati."
    });
  }
});


app.post("/reservations", async (req, res) => {
  const {
    fullName,
    studentIndex,
    roomNumber,
    computerNumber,
    purpose
  } = req.body ?? {};

  const normalizedReservation = {
    fullName: fullName?.trim(),
    studentIndex: studentIndex?.trim(),
    roomNumber: roomNumber?.trim(),
    computerNumber: computerNumber?.trim(),
    purpose: purpose?.trim()
  };

  const hasMissingFields = Object.values(
    normalizedReservation
  ).some((value) => !value);

  if (hasMissingFields) {
    return res.status(400).json({
      success: false,
      error: "Sva polja su obavezna."
    });
  }

  try {
    const result = await pool.query(
      `
        INSERT INTO reservations (
          full_name,
          student_index,
          room_number,
          computer_number,
          purpose
        )
        VALUES ($1, $2, $3, $4, $5)
        RETURNING
          id,
          full_name,
          student_index,
          room_number,
          computer_number,
          purpose,
          created_at
      `,
      [
        normalizedReservation.fullName,
        normalizedReservation.studentIndex,
        normalizedReservation.roomNumber,
        normalizedReservation.computerNumber,
        normalizedReservation.purpose
      ]
    );

    return res.status(201).json({
      success: true,
      reservation: result.rows[0]
    });
  } catch (error) {
    console.error("Reservation creation failed:", error);

    return res.status(500).json({
      success: false,
      error: "Rezervaciju nije moguće sačuvati."
    });
  }
});



app.delete("/reservations/:id", async (req, res) => {
  const id = Number(req.params.id);

  if (!Number.isInteger(id) || id <= 0) {
    return res.status(400).json({
      success: false,
      error: "Invalid reservation ID."
    });
  }

  try {
    const result = await pool.query(
      "DELETE FROM reservations WHERE id = $1 RETURNING id",
      [id]
    );

    if (result.rowCount === 0) {
      return res.status(404).json({
        success: false,
        error: "Reservation was not found."
      });
    }

    res.json({
      success: true,
      deletedId: id
    });
  } catch (error) {
    res.status(500).json({
      success: false,
      error: "Reservation could not be deleted.",
      details: error.message
    });
  }
});

app.listen(PORT, "0.0.0.0", () => {
  console.log(`Equipment reservation backend listening on port ${PORT}`);
});
