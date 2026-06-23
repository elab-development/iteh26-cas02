import React, { useEffect, useState } from "react";

const API_URL = import.meta.env.VITE_API_URL || "http://localhost:3000";

const INITIAL_RESERVATION_FORM = {
  fullName: "",
  studentIndex: "",
  roomNumber: "",
  computerNumber: "",
  purpose: ""
};

export default function App() {
  const [reservationForm, setReservationForm] = useState(
    INITIAL_RESERVATION_FORM
  );
  const [reservations, setReservations] = useState([]);

  const [isLoadingReservations, setIsLoadingReservations] = useState(true);
  const [isSubmittingReservation, setIsSubmittingReservation] = useState(false);

  const [successMessage, setSuccessMessage] = useState("");
  const [errorMessage, setErrorMessage] = useState("");
  const [databaseStatus, setDatabaseStatus] = useState("checking");

  async function fetchReservations() {
    setIsLoadingReservations(true);
    setErrorMessage("");

    try {
      const response = await fetch(`${API_URL}/reservations`);
      const responseData = await response.json();

      if (!response.ok || !responseData.success) {
        throw new Error(
          responseData.error || "Rezervacije nije moguće učitati."
        );
      }

      setReservations(responseData.reservations ?? []);
    } catch (error) {
      setErrorMessage(error.message);
    } finally {
      setIsLoadingReservations(false);
    }
  }

  async function checkDatabaseStatus() {
    try {
      const response = await fetch(`${API_URL}/health`);
      const responseData = await response.json();

      const isDatabaseAvailable =
        response.ok && responseData.database === "available";

      setDatabaseStatus(
        isDatabaseAvailable ? "available" : "unavailable"
      );
    } catch {
      setDatabaseStatus("unavailable");
    }
  }

  useEffect(() => {
    fetchReservations();
    checkDatabaseStatus();
  }, []);

  function handleFormFieldChange(event) {
    const { name, value } = event.target;

    setReservationForm((currentForm) => ({
      ...currentForm,
      [name]: value
    }));
  }

  async function handleReservationSubmit(event) {
    event.preventDefault();

    setIsSubmittingReservation(true);
    setSuccessMessage("");
    setErrorMessage("");

    try {
      const response = await fetch(`${API_URL}/reservations`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json"
        },
        body: JSON.stringify(reservationForm)
      });

      const responseData = await response.json();

      if (!response.ok || !responseData.success) {
        throw new Error(
          responseData.error || "Rezervaciju nije moguće sačuvati."
        );
      }

      setReservationForm(INITIAL_RESERVATION_FORM);
      setSuccessMessage("Rezervacija je uspešno sačuvana.");

      await fetchReservations();
      await checkDatabaseStatus();
    } catch (error) {
      setErrorMessage(error.message);
    } finally {
      setIsSubmittingReservation(false);
    }
  }

  async function handleReservationDelete(reservationId) {
    setSuccessMessage("");
    setErrorMessage("");

    try {
      const response = await fetch(
        `${API_URL}/reservations/${reservationId}`,
        {
          method: "DELETE"
        }
      );

      const responseData = await response.json();

      if (!response.ok || !responseData.success) {
        throw new Error(
          responseData.error || "Rezervaciju nije moguće obrisati."
        );
      }

      setSuccessMessage("Rezervacija je obrisana.");
      await fetchReservations();
    } catch (error) {
      setErrorMessage(error.message);
    }
  }

  return (
    <main className="page-shell">
      <header className="hero">
        <div>
          <p className="eyebrow">Cloud infrastruktura i servisi</p>

          <h1>Computer Reservation System</h1>

          <p className="hero-copy">
            Rezervacija računara u računarskim salama za potrebe studenata.
          </p>
        </div>

        <div className={`status-card status-${databaseStatus}`}>
          <span className="status-dot" />
          Baza: {databaseStatus}
        </div>
      </header>

      <section className="content-grid">
        <article className="panel">
          <h2>Nova rezervacija</h2>

          <form
            className="reservation-form"
            onSubmit={handleReservationSubmit}
          >
            <label>
              Ime i prezime studenta

              <input
                type="text"
                name="fullName"
                value={reservationForm.fullName}
                onChange={handleFormFieldChange}
                placeholder="Petar Petrović"
                required
              />
            </label>

            <label>
              Broj indeksa

              <input
                type="text"
                name="studentIndex"
                value={reservationForm.studentIndex}
                onChange={handleFormFieldChange}
                placeholder="2022/0043"
                required
              />
            </label>

            <label>
              Sala

              <select
                name="roomNumber"
                value={reservationForm.roomNumber}
                onChange={handleFormFieldChange}
                required
              >
                <option value="">Odaberi salu</option>
                <option value="06">06</option>
                <option value="07">07</option>
                <option value="08 i 09">08 i 09</option>
                <option value="11">11</option>
                <option value="19">19</option>
                <option value="40">40</option>
                <option value="61">61</option>
              </select>
            </label>

            <label>
              Broj računara

              <input
                type="text"
                name="computerNumber"
                value={reservationForm.computerNumber}
                onChange={handleFormFieldChange}
                placeholder="50-21"
                required
              />
            </label>

            <label className="full-width">
              Svrha korišćenja računara

              <textarea
                name="purpose"
                value={reservationForm.purpose}
                onChange={handleFormFieldChange}
                placeholder="Ispit"
                rows="4"
                required
              />
            </label>

            <button
              type="submit"
              disabled={isSubmittingReservation}
            >
              {isSubmittingReservation
                ? "Čuvanje..."
                : "Sačuvaj rezervaciju"}
            </button>
          </form>

          {successMessage && (
            <p className="message success">{successMessage}</p>
          )}

          {errorMessage && (
            <p className="message error">{errorMessage}</p>
          )}
        </article>

        <article className="panel reservations-panel">
          <div className="panel-heading">
            <div>
              <h2>Rezervacije</h2>

              <p>
                {reservations.length} sačuvanih rezervacija
              </p>
            </div>

            <button
              type="button"
              className="secondary-button"
              onClick={fetchReservations}
            >
              Osveži rezervacije
            </button>
          </div>

          {isLoadingReservations ? (
            <p className="empty-state">
              Učitavanje rezervacija...
            </p>
          ) : reservations.length === 0 ? (
            <p className="empty-state">
              Nema sačuvanih rezervacija.
            </p>
          ) : (
            <div className="reservation-list">
              {reservations.map((reservation) => (
                <article
                  className="reservation-card"
                  key={reservation.id}
                >
                  <div className="reservation-card-header">
                    <div>
                      <h3>
                        Sala {reservation.room_number},
                        računar {reservation.computer_number}
                      </h3>

                      <p>
                        {reservation.full_name}
                        {" · "}
                        {reservation.student_index}
                      </p>
                    </div>
                  </div>

                  <dl>
                    <div>
                      <dt>Sala</dt>
                      <dd>{reservation.room_number}</dd>
                    </div>

                    <div>
                      <dt>Računar</dt>
                      <dd>{reservation.computer_number}</dd>
                    </div>

                    <div>
                      <dt>Svrha</dt>
                      <dd>{reservation.purpose}</dd>
                    </div>
                  </dl>
                </article>
              ))}
            </div>
          )}
        </article>
      </section>
    </main>
  );
}
