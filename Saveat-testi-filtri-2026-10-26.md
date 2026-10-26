# Saveat — testi e filtri essenziali, 26 ottobre 2026

Versione di partenza verificata: f7f1d28de7b92cc0bfed8eac4b54473b89e1c549. I cinque file pubblici principali corrispondevano al pacchetto clarity-package; l’aggiornamento del 19 ottobre è quindi effettivamente online.

## Modifiche

- Ricerca per alimento, comune e distanza con due nuovi filtri: categoria e tipo di offerta (tutte, in dono, in vendita). Pulsante Azzera filtri mantiene la zona e il testo cercato.
- Filtri applicati nel database PRIMA della paginazione. Categoria, disponibilità e prezzo devono corrispondere allo stesso alimento; gli annunci misti restano riconoscibili e gli alimenti corrispondenti compaiono prima nell’anteprima.
- Nuovo claim: Il cibo buono merita di essere condiviso. Sottotitolo concreto; logo ufficiale e payoff invariati.
- Etichette In dono / In vendita per chi consulta; Dona / Vendi nel modulo di pubblicazione.
- Prenotazione distinta dal ritiro effettivo; riepilogo della prenotazione al posto di ricevuta nei messaggi aggiornati; avvisi nell’app, peso stimato e prezzi concordati descritti senza promesse aggiuntive.
- Pubblica annuncio con numero di alimenti. Quantità sempre vuote, una sola conferma. Revisione di unità, singolari/plurali, profilo, indicazioni e messaggi.
- Intestazione e ricerca più compatte sul telefono; profilo accessibile dal proprio avatar. Il nome dell’account resta nell’etichetta accessibile del pulsante.

## Backend

Aggiunta solo public.saveat_search_filtered, security invoker e search_path vuoto; richiede la stessa autorizzazione di scoperta degli annunci. Ricerca precedente e tutte le tabelle/policy lasciate invariate. RLS annunci/alimenti attiva. Nessuna riesecuzione del file SQL completo.

Test REALI transazionali con dati fittizi: categoria e dono/vendita sullo stesso alimento disponibile, paginazione 20+2 senza duplicati, annunci precedenti senza categoria, anonimo/privato/esercente e assenza dati privati di ritiro. PASS. Rollback completato: utenti test residui 0, annunci test residui 0.

## Verifiche dell’interfaccia

31 controlli sulle larghezze 1440, 1024, 820, 390, 360: nessun overflow, identificatori duplicati o moduli annidati. Filtri combinati, paginazione 22 risultati, azzeramento, priorità agli alimenti corrispondenti negli annunci misti. Quantità vuote per due alimenti e un solo pulsante Pubblica annuncio. Prenotazione SIMULATA: 2 pani in dono e 3 croissant da 1,20 euro, totale 3,60 euro, una conferma. Nessun errore browser registrato.

Lettura REALE da frontend collegato a Supabase: ricerca Frutta e verdura / In dono nell’area Verona 20 km risponde senza errori, nessun risultato disponibile. Nessun annuncio, prenotazione, consegna o profilo reale creato/modificato. 26 file preesistenti di SQL/logo/foto/configurazione/libreria identici. Gli avvisi email di prenotazione restano non configurati; gli avvisi nell’app restano attivi.

## Aggiornamento

La migrazione incrementale aggiornamento-filtri-ricerca.sql è già stata applicata al progetto qifgkxgahfmioeslphjx. Non eseguire supabase.sql o tutte le vecchie migrazioni su un database esistente. Il sito usa la chiave pubblica già configurata, nessun segreto aggiunto al frontend.
