# Saveat — esercenti solo pubblicazione · 16 ottobre 2026

Decisione dell’utente: i privati pubblicano e ritirano; gli account aziendali sono esercenti che pubblicano eccedenze e gestiscono le consegne ai privati. B2B escluso in questa fase, possibile evoluzione successiva.

## Realizzazione
- Home dedicata agli esercenti: Condividi un alimento, I miei annunci, Consegne da gestire, Il mio impatto. Rimossi dal percorso esercente ricerca e annunci altrui. Navigazione a tre voci, nessun tab ritiri ordinario per l’azienda.
- Eventuali ritiri storici aziendali restano conservati e consultabili come Ritiri precedenti; è possibile annullare un vecchio ritiro attivo, non crearne nuovi o variarne le quantità. Nessun ritiro aziendale attivo presente nella verifica iniziale.
- I link diretti alla ricerca riportano l’esercente alla home; gli annunci altrui non diventano prenotabili tramite link.
- Descrizioni in registrazione, profilo, avvisi e conferma salvataggio coerenti con il ruolo. Categoria attività, copertina e logo restano modificabili dal profilo.
- Server: regole centrali saveat_can_discover e saveat_can_collect. Policy RLS aggiuntiva RESTRICTIVE per limitare l’account azienda ai propri annunci; gli alimenti ereditano la visibilità dall’annuncio. Nessuna policy esistente eliminata.
- Ricerche standard e geografiche bloccate per l’azienda. Nuova prenotazione e variazione quantità richiedono account privato, anche con richieste dirette al server. Ridotta anche la proiezione pubblica dei profili altrui per l’esercente.
- Il modello dati mantiene privati e attività; le regole di ruolo sono concentrate in funzioni dedicate per una futura introduzione B2B. Nessun interruttore B2B esposto agli utenti.
- Nessuna modifica distruttiva allo storico, nessuna riesecuzione SQL completo. Annunci propri, prenotazioni ricevute, prezzi concordati, pagamenti al ritiro, resoconti e logo ufficiale preservati.

## Verifiche
- Repository di partenza cf1409c2cafecd74c4a099c5213defc3be5a4684; definizioni effettive di ricerca e policy lette da Supabase qifgkxgahfmioeslphjx prima della modifica.
- Test reali PostgreSQL con dati sintetici e rollback: pubblicazione, RLS annunci/alimenti, ricerca, blocco azienda→privato e B2B, identità, prenotazioni e variazioni private, consegne, avvisi, resoconti, ricevute e storico: PASS.
- Applicata solo aggiornamento-esercenti.sql. Controllo successivo: 0 utenti test residui, 1 policy aggiuntiva restrittiva, 3 funzioni prenotazioni protette e 2 funzioni ricerca protette.
- Interfaccia locale con backend simulato: 21 controlli su tre ruoli, link diretti, gestione annunci propri e modulo prenotazione privato. Schermo 375px senza scorrimento orizzontale. Screenshot anteprima-esercente-mobile-simulata.png mostra un account dimostrativo locale.
- Nessun ritiro commerciale reale creato/modificato e nessuna credenziale cliente utilizzata nelle prove.

Pubblicazione da verificare dopo il commit. Gli esiti finali saranno registrati nel diario locale e nel pacchetto.
