# Saveat — diario unico, aggiornamento 16 ottobre 2026

## Riferimenti consultati
Diario e ZIP del 13 ottobre nelle Fonti locali, senza modificarli. I percorsi /mnt/data non appartengono a questo ambiente Windows. Consultate le ultime richieste della chat Saveat — diario unico e il diario locale del 15 ottobre. Repository remoto confermato al commit 4059e16cc1b5b6b6652c4a3992ac88c6fe98f502. app.js e index.html scaricati dal sito coincidono con la base locale, normalizzati soltanto i fine riga. Conservate comunicazioni guidate, protezioni contatti, avvisi, resoconti e logo ufficiale.

## Decisioni e modifiche
Un solo flusso Condividi un alimento, per attività e privati. Eliminati il selettore Annuncio normale / Eccedenze di oggi e i vecchi comandi per lo schema nel browser. Ogni riga permette nome nuovo, suggerimenti mentre si scrive ed elenco dei propri precedenti. Categoria, nome, descrizione dell’alimento, unità, prezzo, Dona/Vendi, allergeni, peso e contenitore sono richiamati e modificabili prima della pubblicazione. Quantità SEMPRE vuota, anche quando si richiama un altro alimento su una riga già compilata. Date in etichetta, fascia di ritiro e foto da inserire nuovamente. Gli allergeni richiamati vanno ricontrollati con la conferma esplicita esistente.

Ritiro, descrizione generale e pagamenti precedenti possono essere richiamati con il comando nella riga selezionata: questo evita che scegliere il secondo alimento sovrascriva silenziosamente il punto di ritiro comune. Tutti i dati restano modificabili. Da 1 a 20 alimenti, Dona/Vendi per riga, una conferma finale e una sola RPC atomica. Nessuna pubblicazione al richiamo o automatica.

Memoria privata su Supabase, sincronizzata tra dispositivi per account, aggiornata soltanto dopo pubblicazione riuscita e nella stessa transazione. Conserva solo una lista esplicita di campi riutilizzabili, senza quantità, disponibilità, date e foto. Suggerimenti comprendono lo storico del solo proprietario (ultime 500 righe) e la memoria aggiornata, deduplicati per categoria/nome. Cambiare nome o categoria crea una voce distinta; una nuova pubblicazione dello stesso alimento aggiorna le impostazioni. I vecchi annunci e i loro prezzi non vengono aggiornati dal riuso. Gli schemi locali precedenti non vengono importati né cancellati automaticamente.

## Database remoto
Letta prima la funzione effettiva saveat_create_listing e le policy RLS. Applicata solo aggiornamento-memoria-alimenti.sql: due colonne additive negli alimenti per categoria/descrizione, memoria privata con RLS e lettura del titolare, RPC di pubblicazione che riusa la creazione esistente e aggiorna la memoria atomicamente, RPC suggerimenti filtrata per auth.uid(). La funzione di creazione è aggiornata con sostituzione mirata e controllo della definizione attesa; nessuna riscrittura indiscriminata SQL. Prenotazioni, ricevute, disponibilità, contatti e relative protezioni mantenuti.

## Verifiche effettive
PostgreSQL remoto: identità sintetiche, transazione annullata. Passati metadati alimento, offerte miste, aggiornamento memoria, esclusione campi volatili, RLS tra titolare/cliente/estraneo, prezzo prenotato originale 2,50 dopo nuova pubblicazione a 3,50, stock originale invariato, rollback completo su riga non valida, scrittura diretta memoria negata, vendita privati e blocco anonimo. Migrazione poi applicata con COMMIT: memoria=true, RLS=true, utenti di prova residui=0.

Interfaccia locale con backend simulato: 16 controlli passati; deduplica, richiamo campi, quantità/date vuote, nessuna pubblicazione automatica, quantità precedente azzerata, logistica/pagamenti, blocco quantità mancante, unica RPC multi-alimento, modifica dei dati, offerte miste, quantità attuali, nuovo modulo, cambio account, privati, errore server che conserva i dati, flusso unico e logo. Vista mobile a 390 px esaminata; larghezza contenuto uguale alla viewport utile, senza overflow. Sintassi JavaScript valida.

## Limiti e questioni aperte
Questi test NON equivalgono a un ciclo completo con due account reali email/password nel browser. Sessione Saveat disponibile anonima; nessuna password richiesta. Fotocamera e GPS fisici non provati. Restano email applicative, dominio, forma giuridica, moderazione e lancio del diario precedente.

## Pubblicazione
Preparata nella sessione GitHub autenticata già disponibile. L’esito finale viene aggiunto alla copia locale dopo la verifica Pages.
