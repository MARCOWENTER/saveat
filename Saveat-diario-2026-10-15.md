# Saveat — aggiornamento del 15 ottobre 2026

## Base verificata
Consultati diario e pacchetto del 13 ottobre nelle Fonti locali (le copie /mnt/data non appartengono a questo ambiente Windows). Fonti conservate intatte. Repository remoto HEAD edb216437816a1e243992e0efb402cde9ca274e2, coerente con il diario. Sito pubblico HTTP 200 prima delle modifiche.

## Implementazione
Modalità Eccedenze di oggi disponibile per profili attività, facoltativa rispetto all’annuncio normale. Elenco di 10 macro-categorie, specifica facoltativa, quantità/unità, vendita o donazione per ogni riga, fino a 20 righe con un’unica chiamata atomica saveat_create_listing. Ritiro nella giornata corrente in Europe/Rome. Le categorie sono conservate nel nome dell’alimento (Categoria — specifica oppure dettagli non specificati), compatibile con ricerca, modifica e ricevute esistenti. Nessun nuovo campo né SQL eseguito.

Il cliente vede avvertenze sul contenuto, sceglie esplicitamente la quantità (inizialmente zero) e conferma di aver letto le specifiche. Non sono promesse composizioni ignote o sostituzioni automatiche. Gli allergeni restano nel campo esistente.

Schema riutilizzabile su richiesta nel browser, separato per account: categorie, specifiche, unità, prezzo, tipo offerta, pagamenti, comune, punto di ritiro e istruzioni. Quantità, fascia di ritiro, foto e allergeni esclusi e da confermare nuovamente. Pulsante per cancellare lo schema; avviso di uso su dispositivo personale. Nessun salvataggio automatico né sincronizzazione tra dispositivi.

Nuovi annunci delle attività e salvataggi da Modifica usano istruzioni Saveat nel campo contatto; nessun telefono richiesto. I telefoni già presenti in vecchi annunci NON sono bonificati. Il backend esistente può ancora restituirli a prenotanti autorizzati: una garanzia completa richiede controllo delle RPC e una migrazione mirata, con accesso Supabase. La semplice mascheratura grafica non sarebbe una protezione sufficiente. Nessuna messaggistica creata, nessun invio email attivato.

## Verifiche locali
11 controlli nel browser Chrome locale, a 390 px, identità e backend simulati: schema privo di quantità/date/contatti, ripresa con quantità vuote, offerte miste, chiamata atomica unica, prezzi corretti, istruzioni senza telefono, dettagli mancanti espliciti, regressione privati, quantità cliente a zero, conferma obbligatoria e avvertenza. Nessun errore JavaScript; sintassi valida. Layout esaminato visivamente, senza overflow orizzontale. Nessun ciclo autenticato remoto e nessuna prenotazione reale creata.

## Questioni aperte
- Bonifica e protezione server dei contatti storici delle attività.
- Verifica reale con account attività e cliente: pubblicazione, prenotazione, avvisi, ritiro.
- Le categorie sono testo compatibile, non tassonomia normalizzata per statistiche future.
- Lo schema su dispositivo condiviso resta leggibile da chi ha accesso allo stesso browser: usare il comando di eliminazione.
- Restano aperti i temi email, dominio, forma giuridica e lancio già nel diario del 13 ottobre.

## Pubblicazione
Pubblicato tramite sessione GitHub già autenticata nel browser integrato, dopo mancata autenticazione della riga di comando. Commit 95613dd7a5c4ea0fa1be78549b37185135f8632f. GitHub Pages #33, run 38718246155, Success in 47 secondi. Verificato online il selettore nel documento e i riferimenti surplus24; app.js remoto coincide con il sorgente collaudato (normalizzati soltanto i fine riga). Home remota caricata senza accesso utente; contatore restituito dal backend: circa 4 kg, 3 ritiri completati al momento del controllo. Nessuna pubblicazione/prenotazione autenticata remota eseguita. La copia del diario inclusa nel commit di codice precede questo esito finale: questa copia locale di consegna aggiunge la verifica conclusiva.


# Secondo aggiornamento del 15 ottobre — contatti, comunicazioni e resoconti

L’utente ha confermato il perimetro: protezione dei contatti delle attività, comunicazioni guidate in-app, resoconti esportabili e verifiche del flusso. Queste decisioni superano le questioni aperte equivalenti della sezione precedente.

## Backend verificato e aggiornato
Accesso trovato nella sessione Supabase già autenticata del browser. Prima dell’intervento lette le definizioni effettive di creazione, modifica e riepiloghi, la policy sul punto di ritiro e i vincoli degli avvisi; copie preventive locali in work/backend-before.json e work/schema-audit.json, senza segreti. Nessun SQL completo rieseguito. Migrazione mirata aggiornamento-contatti-messaggi-resoconti.sql provata con ROLLBACK e poi applicata con COMMIT. Esito remoto: messaggi=true, resoconti=true, utenti di prova residui=0, completamenti senza data=0.

I contatti storici delle attività non sono eliminati: lettura diretta del dato grezzo consentita al titolare, esclusa ai clienti. Il riepilogo del cliente riceve dal server solo la frase di ritiro Saveat. Nuovi inserimenti/modifiche hanno una protezione server che normalizza il campo contatto. Le differenze degli avvisi di modifica escludono il contatto storico per non riproporlo ai clienti. Nessun avviso storico delle attività conteneva il valore del campo contatto al controllo preventivo. La protezione riguarda i campi gestiti dall’app; testi e foto pubblicati dagli utenti restano da moderare. Contatti dei privati invariati.

## Comunicazioni guidate
Nei riepiloghi dei ritiri: il cliente può chiedere chiarimenti sul punto di ritiro o su contenuto/allergeni e segnalare un ritardo. Il titolare può indicare di avere controllato/aggiornato i dettagli, confermare la fascia o precisare che non può garantire oltre il termine. Ogni tipo si invia una sola volta per prenotazione. Autorizzazione verificata sul server; destinatari privati, storico visibile solo ai partecipanti, nessuna chat libera. Nessuna variazione automatica degli orari e nessun annullamento implicito. L’interfaccia spiega che gli avvisi arrivano in-app e la risposta non è garantita né immediata. Email ancora non attivate.

## Resoconti
In Il mio impatto è disponibile un resoconto per intervallo fino a 366 giorni, filtrabile per cibo condiviso/ritirato, con CSV. Il server restituisce esclusivamente le ricevute dei propri ritiri completati, comprese quelle conservate dopo eliminazione dell’annuncio quando lo snapshot contiene il titolare. Un ritiro con più alimenti conta una volta. Prezzi e pesi sono quelli conservati nelle ricevute. Il valore concordato non verifica gli incassi e non è un documento fiscale. Nessun telefono, indirizzo o nome del cliente nel CSV. Date in Europe/Rome, decimali italiani e protezione da formule nei valori testuali esportati. Per lo storico, la data di completamento è ricostruita da updated_at e marcata come indicativa; i nuovi completamenti hanno una data specifica. Nessuna quantità o ricevuta storica arrotondata.

## Verifiche
Prove sul PostgreSQL remoto con identità sintetiche e transazione annullata: contatti nuovi/storici, RLS, visibilità corretta del punto di ritiro, contatti privati, avvisi senza contatti precedenti, offerte miste, messaggi bidirezionali, retry senza duplicati, ruoli, estranei, destinatari avvisi, blocco dopo completamento, resoconti solo completati, valori ricevute, peso, metadati data, limite periodo e accesso anonimo. Tutte passate. Non equivale a due accessi reali nel browser con email/password.

Prove interfaccia locale con backend simulato: invio e pulsante disabilitato dopo invio, messaggi ricevuti, resoconto con 2 alimenti / 1 ritiro / 3 kg / 5 euro, filtro vuoto, download effettivo CSV e controllo contenuto, escape formule/virgolette, decimali italiani, layout mobile a 390 px esaminato visivamente, sintassi valida.

## Da completare o verificare sul campo
Resta una prova con due account reali nel browser: la sessione Saveat disponibile è anonima. Non sono state richieste password né modificate credenziali. Restano email applicative, dominio, forma giuridica, requisiti di lancio e moderazione come nel diario del 13 ottobre; non inclusi in questo perimetro.

## Pubblicazione interfaccia
Pacchetto preparato per caricamento nella sessione GitHub già autorizzata. L’esito definitivo viene registrato nel diario locale di consegna dopo la verifica Pages.
