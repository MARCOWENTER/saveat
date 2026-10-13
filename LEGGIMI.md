# Saveat MVP

Frontend statico senza compilazione; backend Supabase Auth, PostgreSQL e Storage. Grafica ripresa dal prototipo originale 0.2 recuperato nella cronologia di `MARCOWENTER/saveat`, commit `a2264a5b3a45e91eb6178fa65564e7968ba4b4a2`. La presentazione Saveat del 2018 è stata recuperata e consultata.

## Parti dal SQL Editor dove sei già

1. Apri `supabase.sql`, copia **tutto** e incollalo in una nuova query del SQL Editor Supabase.
2. Premi **Run**. È una sola transazione: tabelle, RLS, funzioni, bucket foto e 7.894 comuni sono inclusi. Non devi creare tabelle o bucket a mano. Attendi il risultato positivo prima di proseguire.
3. Lo script usa nomi `saveat_*`; non elimina altre tabelle. Puoi rieseguirlo. Se avevi già tabelle con questi stessi nomi e una struttura differente, verifica la compatibilità prima di eseguirlo: questo script non migra schemi arbitrari.

## Collegamento: due valori pubblici

In Supabase recupera **Project URL** e **Publishable key** dalle impostazioni del progetto / API Keys. È compatibile anche la chiave `anon` precedente.

Puoi inserirli in `config.js`:

```js
window.SAVEAT_CONFIG = {
  url: 'https://IL-TUO-PROGETTO.supabase.co',
  key: 'LA-TUA-PUBLISHABLE-KEY'
};
```

Oppure pubblica i file con `config.js` vuoto: Saveat mostrerà una schermata che genera il file compilato da scaricare e sostituire. Questi valori sono pubblici e la protezione dei dati è affidata alle RLS. **Non usare secret key o service_role nel sito.**

## Pubblicazione sul tuo GitHub Pages

Nel repository esistente `MARCOWENTER/saveat`, carica nella stessa cartella di `index.html` questi file: `index.html`, `style.css`, `app.js`, `config.js`, `supabase.js`, `favicon.svg`, `.nojekyll`. Sostituisci il vecchio `index.html` e conferma il commit. Puoi omettere dal sito SQL, guida e rapporto di verifica.

Se GitHub Pages è già attivo sul ramo `main`, il nuovo frontend sarà servito allo stesso indirizzo: https://marcowenter.github.io/saveat/. Non occorre un server applicativo separato. Su un altro hosting statico, carica gli stessi file; `_headers` aggiunge intestazioni di sicurezza negli hosting che lo supportano.

Questa consegna non modifica il repository né il progetto Supabase remoto e non certifica che il nuovo MVP sia già online.

## Una configurazione Auth necessaria

In **Authentication → URL Configuration**, imposta:

- Site URL: `https://marcowenter.github.io/saveat/`
- Redirect URLs: `https://marcowenter.github.io/saveat/` e `https://marcowenter.github.io/saveat/#account`

Usa il tuo dominio effettivo se diverso. Mantieni la conferma email. Per utenti esterni configura un servizio SMTP in Supabase: il servizio email predefinito è destinato ai test e ha restrizioni. Il SQL Editor non può impostare queste preferenze Auth o la tua chiave di connessione.

Documentazione: [chiavi API](https://supabase.com/docs/guides/getting-started/api-keys), [redirect Auth](https://supabase.com/docs/guides/auth/redirect-urls), [SMTP](https://supabase.com/docs/guides/auth/auth-smtp).

## Funzioni incluse

- Registrazione email/password, conferma email, login, logout e recupero password.
- Profilo privato oppure attività/azienda agricola. Il tipo è autodichiarato e fissato al primo salvataggio; non equivale a verifica dell’attività. Privati e attività possono scegliere Dona o Vendi; in caso di vendita indicano il prezzo per unità, con pagamento diretto al ritiro.
- Annunci con 1–20 prodotti, quantità per prodotto, prezzo per unità, foto JPG/PNG/WebP fino a 5 MB, date in etichetta e allergeni.
- Ricerca per titolo o alimento e comune, suggerimenti da elenco ISTAT completo.
- Prenotazione di più prodotti dello stesso annuncio in una sola transazione. Blocco dell’annuncio prima di verificare e decrementare disponibilità; rollback completo se un prodotto è insufficiente. UUID di richiesta per evitare doppio decremento in caso di retry.
- Prenotazione confermata automaticamente → cliente segnala «Ho ritirato» → pubblicante conferma il ritiro; annullamento da entrambe le parti con restituzione della quantità una sola volta; scadenza al termine della fascia di ritiro; chiusura dell’annuncio con annullamento delle prenotazioni attive.
- Indirizzo e contatto privati, visibili solo al pubblicante e al prenotante finché la prenotazione è attiva. Nello storico concluso il cliente non riceve più quei dettagli.
- Quantità frazionate per kg/litri; intere per pezzi/confezioni. I prodotti con data “da consumare entro” devono essere ritirati entro quella data.

La scadenza viene applicata in base all’ora del database: l’interfaccia e le funzioni mostrano `expired` al termine del ritiro senza richiedere cron. Le righe grezze possono conservare `reserved`/`confirmed` fino alla successiva operazione; il residuo può essere rimesso online modificando lo stesso annuncio con un nuovo termine di ritiro; le prenotazioni scadute non tornano attive.

## Verifica prima di aprire agli utenti

Il rapporto allegato distingue i controlli locali dai controlli remoti ancora necessari. Dopo aver collegato il progetto:

1. Crea due account e conferma le email. Con il primo pubblica due alimenti e una foto.
2. Senza login controlla ricerca e suggerimenti “Ver”; indirizzo e contatto non devono apparire.
3. Con il secondo prenota entrambi gli alimenti. Verifica quantità aggiornate e dettagli di ritiro.
4. Annulla e controlla il ripristino. Ripeti, conferma con il pubblicante e registra il ritiro durante la fascia prevista.
5. Prova conferma email e recupero password dal dominio pubblicato. Controlla il Security Advisor di Supabase.

Il lancio pubblico richiede anche il regolamento alimenti ammessi del pilota, informativa privacy/condizioni del servizio, gestione segnalazioni e verifica operativa delle attività. Questi contenuti non erano recuperabili nei riferimenti e non sono stati inventati. Non è inclusa una verifica legale né una gestione pagamenti online.

## Limiti operativi

Non sono inclusi chat, notifiche push a sito chiuso, mappa, consegna, pagamenti online, moderazione o verifica documentale. Gli avvisi dentro Saveat sono presenti; l’invio email resta in attesa del collegamento Brevo e del servizio di invio. Le prenotazioni ricevute si controllano in I miei Save. Lo storico mostra le ultime 100 pubblicazioni; la ricerca pagina 20 annunci per volta. Foto caricate prima di una pubblicazione fallita possono restare inutilizzate: prevedere una pulizia amministrativa degli oggetti orfani. Le foto sono pubbliche: non caricare contatti, indirizzi o persone.

## Fonti e licenze

- [Dataset ISTAT](https://www.istat.it/classificazione/codici-dei-comuni-delle-province-e-delle-regioni/): file XLSX aggiornato al 21 febbraio 2026, 7.894 comuni. Incorporato nello script; non richiede download all’avvio. Attribution: Istat, riuso secondo le condizioni [note legali ISTAT](https://www.istat.it/note-legali/).
- Supabase JS 2.117.3, copia locale della distribuzione UMD ufficiale, licenza MIT (vedi `SUPABASE-LICENSE.txt`).

## Foto e donazioni del residuo (12 ottobre 2026)

Le foto sono mostrate intere e adattate in proporzione. Aggiungi foto sceglie dalla galleria; Scatta foto richiede la fotocamera sui telefoni compatibili. JPG/PNG/WebP fino a 25 MB vengono adattati prima dell’invio (massimo 5 MB); HEIC non leggibili richiedono conversione in JPG.

In Modifica ogni alimento offre Dona/Vendi e prezzo unitario per le nuove prenotazioni. Quantità totale include quelle già ritirate: per 5 confezioni, 3 ritirate e 2 rimaste, lascia 5 e scegli Dona. Se la fascia è scaduta, imposta un nuovo termine. I ritiri segnalati devono prima essere confermati; il rinnovo non supera la scadenza alimentare. Le vecchie ricevute conservano prezzo e fascia iniziale.

Per aggiornare un database esistente usare aggiornamento-foto-donazioni.sql dopo le migrazioni precedenti; supabase.sql contiene già la versione completa.

## Contatore kg salvati

La Home mostra il totale indicativo dei ritiri completati e confermati, includendo vendite e donazioni. Peso per unità facoltativo in grammi nella pubblicazione/modifica. Per kg si usa la quantità; senza peso si stimano 500 g per pezzo/confezione e 1 kg per litro. Pesi e totali dei ritiri conclusi si conservano nello storico anche dopo modifica/eliminazione dell’annuncio. Per database esistente applicare aggiornamento-contatore.sql dopo le precedenti migrazioni; supabase.sql lo include già.

## Borsa e contenitore per il ritiro

Promemoria sempre visibile nell’annuncio e nelle prenotazioni attive: Porta sempre una borsa per il ritiro. Confezioni: confezione inclusa. Per pezzi/kg/litri, casella Fornisco io il contenitore; se non selezionata, chi prenota vede Porta anche un contenitore. La scelta è per alimento e si modifica dal proprio annuncio; le prenotazioni già effettuate conservano la promessa iniziale. I dati antecedenti senza indicazione restano Contenitore da concordare, finché aggiornati dal proprietario. Per aggiornamento database: aggiornamento-contenitore.sql dopo aggiornamento-contatore.sql; supabase.sql lo include.

## Correzioni e pagamenti — 13 ottobre 2026

La descrizione è mostrata in elenco, dettaglio, propri annunci e ricevute. Modifica comprende titolo, descrizione, nome, unità, quantità, prezzo/Dona, foto (anche rimozione), data/scadenza, allergeni, peso, contenitore, comune, orari, indirizzo, contatto e istruzioni. Prenotazioni attive ricevono avviso in-app; prezzo e ricevuta iniziale rimangono conservati. Le informazioni correnti sono mostrate a fianco delle correzioni. Per cambio unità con stock già impegnato occorre indicare il fattore di conversione e aggiornare il totale. Quantità totale non inferiore all’impegnato; date coerenti con la scadenza. Correggere un annuncio annullato non lo riapre.

Vendita: Contanti, Carta/POS e Satispay. Metodi mostrati prima di prenotare e nel riepilogo; nessun pagamento gestito dall’app. Donazioni senza campo pagamento. Annunci vecchi senza indicazioni: Da concordare, nessun metodo inventato. Database: aggiornamento-correzioni-pagamenti.sql, già applicato al progetto Saveat; incluso nel supabase.sql completo.
