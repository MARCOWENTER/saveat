# Stato della verifica

9 ottobre 2026. MVP consegnato come codice da collegare e pubblicare.

## Superati

Il file SQL finale è stato eseguito su PostgreSQL locale tramite PGlite, con schemi Auth/Storage simulati e ruoli separati `anon` / `authenticated`. La verifica ha incluso anche tutti i 7.894 comuni incorporati e la seconda esecuzione dello script.

14 controlli passati:

1. Script completo eseguibile.
2. Seconda esecuzione senza perdita dei dati di test.
3. Vendita da account privato bloccata nel database.
4. Indirizzo nascosto prima della prenotazione e profili isolati.
5. Modifica diretta delle disponibilità negata.
6. Quantità insufficienti in un annuncio multi-prodotto provocano rollback completo.
7. Retry con lo stesso identificativo non decrementa due volte.
8. Indirizzo visibile al prenotante autorizzato.
9. Cliente escluso dalla conferma del ritiro riservata al pubblicante.
10. Utenti estranei esclusi dalle prenotazioni private; richiesta superiore alla disponibilità negata.
11. Annullamento ripristina la quantità una sola volta e revoca l’accesso all’indirizzo.
12. Conferma, ritiro e chiusura funzionano; annunci chiusi nascosti agli anonimi.
13. Storico conservato senza contatti nelle prenotazioni concluse.
14. Tipo di account immutabile dopo la scelta iniziale.

Sintassi JavaScript verificata con Node.js. Distribuzione Supabase JS locale fissata alla versione 2.117.3. Prototipo originale recuperato dalla cronologia del repository, non ricostruito a memoria.

## Non ancora verificati

- Esecuzione sul progetto Supabase dell’utente, API REST, Auth/email, Storage reale e collegamento con i valori pubblici del progetto: mancano Project URL e Publishable key.
- Stress test con connessioni PostgreSQL simultanee: il motore locale serializza le richieste. Il codice usa un lock di riga sull’annuncio e una transazione per prevenire l’overselling, ma il carico concorrente remoto va verificato prima del lancio.
- Verifica visiva e interazioni in browser: il browser disponibile non ha raggiunto il server locale (timeout in due tentativi).
- Pubblicazione e verifica del dominio: nessuna modifica inviata al repository o al progetto Supabase.

Non si dichiara questo MVP già online o certificato pronto per la produzione. La guida contiene i passaggi per completare la connessione e i controlli remoti.

## Collegamento remoto verificato

Project URL e chiave pubblica inseriti. API Supabase raggiungibile: lettura del comune Verona riuscita e funzione saveat_search eseguita correttamente, con elenco vuoto in assenza di annunci. Auth, upload foto e prenotazioni fra account reali restano da verificare. Nessuna pubblicazione effettuata.
