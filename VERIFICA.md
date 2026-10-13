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

## Registrazione separata

Aggiunti modulo Registrati con nome e cognome, email, doppia password e tipo account, ritorno all’annuncio dopo accesso, invio manuale di nuova conferma e messaggi italiani per errori Auth. Dati nome/cognome conservati nei metadati Auth; profilo pubblico compatibile con lo schema esistente. Verificati localmente sei aspetti del percorso con un client Auth simulato, senza inviare email di test. Il limite del servizio email Supabase resta indipendente da queste modifiche.

### Foto e residuo, 12/10/2026

21 scenari database locali passati (PGlite Auth/Storage simulati), inclusi 5 iniziali/3 ritirati/2 gratuiti, prezzi e date delle ricevute conservati, rinnovo e restituzione scaduti senza doppio stock, foto limitate al proprietario. Foto 4000x3000 adattata a 1800x1350, scelta galleria distinta da capture environment. Supabase remoto: migrazione riuscita, «Success. No rows returned». Fotocamera fisica e flusso autenticato sul telefono richiedono prova reale; non simulata come verifica hardware.

### Contatore kg salvati

25 scenari database locali passati, compreso conteggio kg/peso indicato/stime; solo ritiri completati, retry senza doppio conteggio, totali conservati dopo modifica ed eliminazione; pubblico riceve esclusivamente totali aggregati. Nessuna prenotazione reale creata per test.

### Borsa e contenitore

26 scenari database locali passati: confezioni incluse, cibo sfuso con/senza contenitore, snapshot per prenotazione conservato dopo modifica ed eliminazione, scrittura diretta negata. UI: casella per sfuso, testo esplicativo, confezioni senza campo extra, promemoria borsa e riepilogo multi-alimento; dati precedenti senza indicazione non inventati. Regressioni accesso/cambio account/ricerca e Dona-Vendi passate.

## Correzioni complete e pagamenti

Script completo eseguito due volte in PostgreSQL locale PGlite. Casi integrati passati: descrizione/metadata/logistica con prenotazione attiva, conversione pezzi→kg→pezzi con stock corretto, cancellazione idempotente, originale prezzo/quantità/peso e pagamento storico conservati, notifiche private e riattivate, isolamento proprietario/anonimo, minimo impegnato e conversione atomica, scrittura diretta vietata. UI: payload descrizione, allergeni, date e pagamenti verificato, donazione/vendita, foto/avvisi/riepiloghi in regressione; descrizione multilinea escaped e legacy pagamento non inventato. Supabase remoto migrazione: Success. No rows returned. Nessun annuncio reale modificato per prove. Prova completa del modulo con account reale ancora da effettuare.

Avvisi e profilo: controllati valori prima/dopo, destinatario pubblicante per annullamento cliente, nessun duplicato, privacy tra account, menu apertura/chiusura/Escape/uscita.

Verificati controlli quantità con incrementi 1 e 0,1, tastiera, disponibilità massima e pezzi interi. Prove database per nuova prenotazione di vendita e donazione, destinatario privato, retry senza duplicati e coda email.
