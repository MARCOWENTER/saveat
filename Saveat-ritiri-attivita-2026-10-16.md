# Saveat — ritiri modificabili e attività · 16 ottobre 2026

Richiesta: consentire al cliente di aumentare o diminuire le quantità prenotate, aggiornare le disponibilità e avvisare il pubblicante; categoria aziendale con copertina automatica, conservando il logo caricato.

## Comportamento
- I miei ritiri → Modifica quantità: nuovo totale per ciascun alimento già prenotato. Zero rimuove una riga; per togliere tutto resta Annulla prenotazione. Non aggiunge alimenti nuovi che non facevano parte del ritiro.
- Una conferma esplicita salva tutte le variazioni e notifica chi pubblica, con quantità prima/dopo e totale. Prima della conferma nessuna modifica.
- Aumenti solo se disponibili al salvataggio; riduzioni restituiscono stock. Operazione atomica con blocco annuncio e prenotazione, revisione contro modifiche obsolete e identificatore per retry.
- Prezzo unitario concordato mantenuto anche per l’aumento dello stesso alimento; nessun ricalcolo al nuovo prezzo dell’annuncio. Unità e pesi della ricevuta conservati, anche se il magazzino è stato convertito.
- Solo cliente, ritiro attivo, annuncio aperto, fascia non scaduta e ritiro non già segnalato. Storico delle variazioni con fotografie JSON delle righe prima/dopo, protetto per partecipanti. Prenotazioni concluse non riscritte.
- Avviso in-app aggiornato ad ogni variazione; coda email predisposta, invio email ancora non configurato.
- 13 categorie: supermercato/alimentari, ristorante/pizzeria, ortofrutta, azienda agricola, panificio, pasticceria, gastronomia/rosticceria, macelleria/salumeria, pescheria, bar/caffetteria, hotel/mensa/catering, negozio specializzato, altra attività alimentare.
- Scelta richiesta alle nuove iscrizioni aziendali e al salvataggio del profilo azienda. Le aziende esistenti senza categoria restano utilizzabili: nessuna categoria indovinata automaticamente.
- Copertina grafica con simboli, titolo categoria e indicazione che le disponibilità effettive sono negli annunci. Anteprima immediata e modifica dal profilo. Logo facoltativo separato, già supportato.

## Verifiche
- Stato GitHub letto: main 4a91fab26e805f08ecb75e04b82b07567189a3ed prima del lavoro.
- Definizioni e vincoli effettivi Supabase letti prima di scrivere la sola migrazione incrementale aggiornamento-ritiri-attivita.sql.
- Test reali PostgreSQL con identità sintetiche e rollback: quantità, disponibilità, stock insufficiente e atomicità, retry, revisioni obsolete, estranei e RLS, storico, avvisi destinatario corretto, categoria, prezzi concordati, conversione unità, rimozione singola riga, annullamento, ritiri segnalati/scaduti e anonimo: PASS.
- Migrazione applicata: Success. Controllo successivo: 0 utenti di prova residui, 0 variazioni reali create, RLS storico true, esecuzione anonima false, tre nuove funzioni presenti.
- Browser locale con backend simulato: otto controlli automatici PASS; modifica due quantità e totale live, errore rete e retry con stesso identificatore, riepilogo aggiornato, anteprima categoria dinamica. Vista iscrizione 375 px e dialogo 360 px senza scorrimento orizzontale. Nessuna prenotazione commerciale o iscrizione reale eseguita.
- Logo ufficiale invariato. Nessuna riesecuzione SQL completa.

Pubblicazione web: da verificare dopo questo commit; gli esiti finali saranno aggiunti al diario locale e all’archivio consegnato.
