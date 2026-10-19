# Saveat — nuova disposizione desktop · 19 ottobre 2026

Richiesta approvata: migliorare la visualizzazione da computer prendendo come riferimento la distribuzione degli spazi di Too Good To Go, mantenendo identità Saveat e semplicità da telefono.

## Modifiche
- Superata la colonna fissa da 760px: sfondo a tutta finestra e contenuti centrati fino a 1360px, circa 1300px utili.
- Menu unico superiore da 1000px; navigazione fissa inferiore su telefono/tablet. Logo originale invariato.
- Home con titolo e azioni affiancati a una nuova composizione SVG originale di alimenti; nessuna immagine copiata dal sito di riferimento e nessun caricamento esterno.
- Ricerca direttamente in home per alimento, comune suggerito e distanza. Trasferisce i valori alla ricerca esistente; mantiene la zona abituale o scelta. Il pulsante posizione conserva il raggio selezionato.
- Home mostra fino a sei annunci; griglia tre colonne desktop, due tablet, elenco compatto mobile. Foto complete con object-fit contain, singoli alimenti e relativi prezzi ancora visibili negli annunci multipli.
- Impatto collettivo spostato dopo gli annunci; breve sezione Come funziona con ritiro e pagamento al ritiro.
- Ricerca desktop con filtri e pulsante affiancati. Messaggi di assenza risultati preservati.
- Scheda annuncio: informazioni/foto a sinistra, scelta quantità e conferma a destra; sequenza verticale su mobile. Controlli quantità, incremento per kg/litri, prezzi e conferma unica preservati. Desktop omette il selettore ridondante dell’incremento per pezzi/confezioni, dove è disponibile solo l’incremento intero.
- Area esercente con azioni e impatto affiancati; riepiloghi su due colonne. Profili e moduli mantengono una larghezza leggibile.
- Nessuna modifica alle regole privati/esercenti, alla memoria alimenti, ai prezzi concordati, al database o alle RLS. B2B resta disattivato.

## Verifiche
- Nove controlli DOM/layout in cinque configurazioni (1440, 1024, 820, 390 e 360px): PASS. Griglie 3/2/1 colonne e nessuna larghezza oltre schermo.
- Test locale con backend simulato: ricerca Pane/Vicenza/50 km, prenotazione unica con due righe e totale 3,60 €, ricevuta coerente; 1,5 kg a 3,80 €/kg dà 5,70 €. Modulo pubblicazione esercente ancora con quantità vuota.
- Backend reale in sola lettura: caricamento impatto, suggerimenti comuni e ricerca reale Verona/20 km riusciti; al controllo non ci sono alimenti disponibili nella zona.
- Confronto byte/hash su 26 file invarianti: logo, configurazione, avatars.js, libreria Supabase e tutti gli SQL identici al pacchetto precedente. Nessun SQL eseguito.
- Nessuna nuova prenotazione, iscrizione, pubblicazione o modifica profilo reale. Nessuna autorizzazione GPS richiesta.

Pubblicazione da verificare dopo il commit; gli esiti finali saranno aggiunti al diario locale e al pacchetto.
