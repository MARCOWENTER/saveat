# Saveat — correzioni prima del lancio, 28 ottobre 2026

Aggiornamento della versione 9bc20151666480408d971b912685ee460f900d88.

## Correzioni

- Messaggi legati alla schermata: l'invito ad accedere e gli errori di altre operazioni non rimangono nella ricerca libera. Le conferme della pubblicazione o della prenotazione restano nella schermata di destinazione corretta.
- Vai al contenuto sposta il focus al contenuto della pagina attuale, senza cambiare schermata.
- Busta mista conserva la propria caratteristica anche se il nome viene cambiato. La caratteristica passa per pubblicazione, modifica, ricerca, memoria privata, prenotazione, riepilogo e modifica quantità. Il contenuto indicativo resta obbligatorio anche sul server.
- I dati dei suggerimenti aggiornano anche gli errori di validazione: un nome compilato dal pulsante Busta mista non resta segnalato come mancante.
- Modifica quantità è visibile nella scheda del ritiro, fuori da Altre azioni. Annulla prenotazione resta tra le azioni secondarie.
- Raggio di interesse nascosto e non richiesto per gli esercenti sia in registrazione sia nel profilo. Rimane per i privati.
- Un solo pulsante principale Condividi un alimento nella Home dell'esercente.
- Avviso di notifiche compatto e senza ripetizione nella pagina Avvisi.
- Nelle anteprime ogni prodotto compare una volta: i primi tre con quantità e prezzo, gli eventuali altri con nome; contenuto indicativo delle buste e punto esatto di ritiro restano visibili.
- Controllo quantità semplificato: pulsanti e campo numerico, senza selettore del passo. Passo intero per pezzi/confezioni, decimale per kg/litri.
- Scelta del punto di ritiro coerente tornando al modulo. Nuovo punto resta vuoto se scelto volontariamente; un indirizzo precedente già richiamato rimane selezionato. Messaggio più chiaro dopo la modifica dell'indirizzo.

## Database

Applicata solo aggiornamento-buste-rinominabili.sql. Aggiunge il metadato nullable is_mixed_bag ad alimenti e righe di prenotazione e adegua otto funzioni esistenti. Non riscrive le righe storiche. Per i dati precedenti privi del metadato resta la lettura compatibile del nome Busta. Le nuove prenotazioni conservano il tipo busta insieme al nome e al prezzo iniziali. Le funzioni sono protette da un controllo di versione prima della sostituzione; RLS e autorizzazioni esistenti non vengono modificate. Non rieseguire indiscriminatamente lo schema completo.

## Verifiche

- Prova sul servizio PostgreSQL reale con dati sintetici e rollback: rinomina della busta, contenuto obbligatorio, memoria privata, nomi e prezzi delle prenotazioni originarie, nuove ricevute e riepiloghi: PASS.
- Applicazione mirata della migrazione: Success. No rows returned.
- Sei gruppi di regressione reali dopo l'applicazione, con rollback: buste, ruoli, filtri, contatti/messaggi/resoconti, punti di ritiro, variazioni quantità: PASS.
- Interfaccia simulata: busta rinominata pubblicata una sola volta, richiamo con quantità vuota, prezzo/unità conservati, correzione errore nome, salto al contenuto, messaggi di pagine precedenti nascosti, Modifica quantità subito visibile, raggio esercente nascosto, singolo pulsante Home, nuovo punto non sovrascritto.
- 21 controlli responsive su sette schermate a 360/768/1440 pixel: nessuna fuoriuscita laterale. Nessun errore registrato nel browser dell'anteprima durante le prove.

Le prove SQL usano ruoli e identità sintetiche sul database reale; non sostituiscono un collaudo con due accessi reali, caselle email, GPS e telefoni fisici. Le azioni della UI dimostrativa non pubblicano dati reali.

## Rinvii concordati

Privacy, condizioni d'uso e contatti di assistenza rinviati esplicitamente dall'utente. Nessun dato organizzativo inventato. Restano da collaudare con account dedicati email di autenticazione, recupero password, caricamento definitivo immagini, GPS fisico e concorrenza da due browser.
