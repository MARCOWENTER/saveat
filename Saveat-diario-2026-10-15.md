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
Da aggiornare dopo il tentativo con gli accessi disponibili.
