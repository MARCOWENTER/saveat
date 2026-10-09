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
- Profilo privato oppure attività/azienda agricola. Il tipo è autodichiarato e fissato al primo salvataggio; non equivale a verifica dell’attività. Privati solo regalo; attività regalo o vendita, con pagamento diretto al ritiro.
- Annunci con 1–20 prodotti, quantità per prodotto, prezzo per unità, foto JPG/PNG/WebP fino a 5 MB, date in etichetta e allergeni.
- Ricerca per titolo o alimento e comune, suggerimenti da elenco ISTAT completo.
- Prenotazione di più prodotti dello stesso annuncio in una sola transazione. Blocco dell’annuncio prima di verificare e decrementare disponibilità; rollback completo se un prodotto è insufficiente. UUID di richiesta per evitare doppio decremento in caso di retry.
- Prenotato → confermato dal pubblicante → ritirato dal pubblicante; annullamento da entrambe le parti con restituzione della quantità una sola volta; scadenza al termine della fascia di ritiro; chiusura dell’annuncio con annullamento delle prenotazioni attive.
- Indirizzo e contatto privati, visibili solo al pubblicante e al prenotante finché la prenotazione è attiva. Nello storico concluso il cliente non riceve più quei dettagli.
- Quantità frazionate per kg/litri; intere per pezzi/confezioni. I prodotti con data “da consumare entro” devono essere ritirati entro quella data.

La scadenza viene applicata in base all’ora del database: l’interfaccia e le funzioni mostrano `expired` al termine del ritiro senza richiedere cron. Le righe grezze possono conservare `reserved`/`confirmed` fino alla successiva operazione; la disponibilità non viene riproposta dopo la scadenza dell’annuncio.

## Verifica prima di aprire agli utenti

Il rapporto allegato distingue i controlli locali dai controlli remoti ancora necessari. Dopo aver collegato il progetto:

1. Crea due account e conferma le email. Con il primo pubblica due alimenti e una foto.
2. Senza login controlla ricerca e suggerimenti “Ver”; indirizzo e contatto non devono apparire.
3. Con il secondo prenota entrambi gli alimenti. Verifica quantità aggiornate e dettagli di ritiro.
4. Annulla e controlla il ripristino. Ripeti, conferma con il pubblicante e registra il ritiro durante la fascia prevista.
5. Prova conferma email e recupero password dal dominio pubblicato. Controlla il Security Advisor di Supabase.

Il lancio pubblico richiede anche il regolamento alimenti ammessi del pilota, informativa privacy/condizioni del servizio, gestione segnalazioni e verifica operativa delle attività. Questi contenuti non erano recuperabili nei riferimenti e non sono stati inventati. Non è inclusa una verifica legale né una gestione pagamenti online.

## Limiti operativi

Non sono inclusi chat, notifiche automatiche, mappa, consegna, pagamenti online, moderazione o verifica documentale. Le prenotazioni ricevute si controllano in I miei Save. Lo storico mostra le ultime 100 pubblicazioni; la ricerca pagina 20 annunci per volta. Foto caricate prima di una pubblicazione fallita possono restare inutilizzate: prevedere una pulizia amministrativa degli oggetti orfani. Le foto sono pubbliche: non caricare contatti, indirizzi o persone.

## Fonti e licenze

- [Dataset ISTAT](https://www.istat.it/classificazione/codici-dei-comuni-delle-province-e-delle-regioni/): file XLSX aggiornato al 21 febbraio 2026, 7.894 comuni. Incorporato nello script; non richiede download all’avvio. Attribution: Istat, riuso secondo le condizioni [note legali ISTAT](https://www.istat.it/note-legali/).
- Supabase JS 2.117.3, copia locale della distribuzione UMD ufficiale, licenza MIT (vedi `SUPABASE-LICENSE.txt`).
