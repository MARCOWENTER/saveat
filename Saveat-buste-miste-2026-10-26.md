# Saveat — buste miste e singoli alimenti, 26 ottobre 2026

Base verificata: commit 867c0f7d6a5be15115326c0cd5a653cf1ce4a7e0.

Un solo modulo e una sola conferma di pubblicazione. Foto facoltativa visibile in apertura di ogni voce. Suggerimento Busta mista nel campo nome: compila nome, categoria Altri alimenti e unità; il contenuto indicativo va descritto con poche parole. Nessun elenco degli articoli interni richiesto. Quantità riferita alle buste, con incremento intero e prezzo per busta. Singoli alimenti e buste possono coesistere nello stesso annuncio. Categoria, date, allergeni e peso restano nei dettagli facoltativi.

Una busta usa l’unità esistente confezioni nel database: nessuna conversione o modifica delle quantità storiche. L’etichetta busta/buste si applica alle confezioni il cui nome inizia con Busta (es. Busta mista, Busta frutta). Cambiando nome/unità, l’interfaccia segue la voce aggiornata. Le prenotazioni mantengono nome, unità e prezzo originali.

La memoria privata esistente conserva nome, descrizione, categoria, Dona/Vendi e prezzo. Il richiamo mantiene quantità e date vuote. Le foto vanno selezionate nuovamente per tenerle aggiornate. Nessuna pubblicazione automatica.

Contenuto indicativo e variabilità sono espliciti nella scheda, compresa la foto rappresentativa. La modifica dell’annuncio permette di correggere la descrizione della voce; una patch mirata della funzione esistente salva il campo e lo include negli avvisi di variazione. Nessuna modifica a tabelle, RLS, lock, prezzi concordati o logica di disponibilità. Non rieseguire SQL completo o vecchie migrazioni. La sola aggiornamento-contenuto-buste.sql è già stata applicata con Success.

Prove REALI su Supabase con dati fittizi in transazione poi ROLLBACK: pubblicazione busta8 a4euro e yogurt10 in dono; contenuto persistito; memoria privata priva di quantità/date; prenotazione buste2+yogurt3, totale8euro e disponibilità6/7; correzione contenuto e prezzo nuovo5euro con avviso e prezzo prenotato4euro conservato; modifica ritiro a buste3+yogurt1, totale12euro e disponibilità5/9; quantità oltre disponibilità respinta senza effetti; modifica da terzo negata. Pulizia verificata: utenti test0, annunci test0; RLS attiva per annunci/alimenti/memoria.

Prove UI SIMULATE: pubblicazione unica con due voci; richiamo contenuto/prezzo con quantità vuota; prenotazione buste2+yogurt3 totale8euro; foto adattata localmente senza upload remoto. Dodici controlli di layout su pubblicazione/dettaglio/modifica alle larghezze1440,1024,820,390,360: nessun overflow, ID duplicato o modulo annidato. Nessun errore browser. Nessun profilo, annuncio o prenotazione reale modificato dalle prove.

Logo e file preesistenti SQL/config/libreria invariati. Email di prenotazione ancora non configurate; avvisi in-app mantenuti.
