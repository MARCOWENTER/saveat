# Saveat — elenco compatto e permessi foto, 16 ottobre 2026

## Base e decisioni
Base pubblicata 5a7418c3ad5e2f4513013b017ea4c5f7ea6ad36d. L’utente ha richiesto un elenco di prodotti con riquadri/righe e solo dati indispensabili, aprendo i dettagli al clic. Confermato anche il consenso alla restrizione dell’elenco file foto proposta nella ripresa precedente. Fonti e logo ufficiale conservati.

## Interfaccia
In Home e Trova cibo, righe compatte interamente cliccabili: miniatura completa senza ritagli o segnaposto, titolo massimo due righe, pubblicante con foto/logo se presente, comune e distanza indicativa quando disponibile, quantità/unità per alimento singolo o numero di alimenti, Dona/Vendi e prezzo, termine ritiro breve in Europe/Rome. Gratis e prezzi a pagamento distinti negli annunci misti. Prezzo da confrontare mostrato solo con unità coerenti; altrimenti Prezzi nei dettagli. Annunci propri identificati con Il tuo annuncio / Gestisci.

Descrizioni, conservazione, allergeni, pagamenti e quantità da prenotare restano nella scheda completa già esistente. Nessuna modifica alla pubblicazione o alle prenotazioni. Ogni riquadro è un collegamento nativo unico, accessibile anche da tastiera, senza pulsanti o collegamenti annidati.

## Verifiche locali
14 controlli con dati/backend simulati passati: collegamento unico, prezzo/unità/quantità, nessun dettaglio lungo in elenco, pubblicante/zona/distanza/ritiro, donazione, distanza assente non inventata, alimenti multipli, offerte miste, unità diverse, annunci propri, segnaposto senza foto, protezione HTML, nessun comando annidato e logo ufficiale. Apertura scheda e ritorno controllati nel browser: descrizione completa, allergeni, pagamenti e controlli prenotazione presenti. Vista mobile 390 px esaminata, nessun overflow; riquadri di esempio alti circa 190–240 px contro le precedenti schede estese. Sintassi JavaScript valida. Non equivale a una nuova prenotazione remota reale.

## Permessi foto
Sostituita in una transazione la sola policy SELECT del bucket saveat-avatars: elenco/lettura metadati riservati al titolare autenticato nella propria cartella. Inserimento/rimozione già limitati al titolare. Il bucket resta pubblico per mostrare le immagini negli annunci tramite URL. Nessun file cancellato e nessun cambiamento al bucket delle foto alimenti. Il precedente blocco di approvazione è superato dal consenso esplicito dell’utente in questa ripresa; operazione approvata e applicata. Migrazione incremento: aggiornamento-elenco-foto-privato.sql. Anche la migrazione iniziale foto nel pacchetto è allineata alla policy più restrittiva per nuove installazioni; non rieseguire SQL completo.

## Pubblicazione
Esito finale aggiunto alla copia locale dopo controllo GitHub Pages.

## Verifica remota permessi completata
Test PostgreSQL remoto con identità sintetiche via claim e un record Storage temporaneo, transazione annullata: il titolare legge il proprio record, estraneo e anonimo non lo vedono. Esito PASS, bucket pubblico=true. Nessun file binario caricato o cancellato. Apertura della scheda anche con Invio da tastiera verificata nel browser locale.
