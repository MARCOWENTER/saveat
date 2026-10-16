# Saveat — anteprima di più alimenti, 16 ottobre 2026

## Problema
L’utente segnala che un annuncio con due articoli sembra contenere solo il primo nel riquadro; il secondo compare entrando nella scheda. La riga compatta mostrava il titolo dell’annuncio (spesso generato dal primo alimento) e il conteggio, senza i nomi dei singoli articoli.

## Correzione
Con almeno due alimenti disponibili, il riquadro mostra i primi tre nomi, ciascuno con quantità/unità e prezzo per unità o Gratis. Se ci sono più di tre alimenti, mostra + altri X alimenti · vedi tutti. La scheda completa rimane raggiungibile cliccando in qualunque punto del riquadro. Sono mostrati solo alimenti con disponibilità positiva.

Quando il titolo dell’annuncio coincide con il nome di un alimento, il riquadro usa un titolo riepilogativo (es. 2 alimenti da salvare); se resta disponibile un solo alimento, ne usa il nome. I titoli personalizzati diversi dai nomi restano invariati. Questo riguarda solo la presentazione del riquadro: nessun titolo salvato viene riscritto.

## Verifiche
14 regressioni dell’elenco e 8 controlli mirati con dati/backend simulati, tutti passati: entrambi i nomi presenti per due alimenti, quantità/prezzi corretti per riga, titolo riepilogativo, titolo personalizzato, limite di tre anteprime e +17 per un annuncio da 20, esclusione esauriti e aggiornamento titolo visibile, annuncio singolo compatto, protezione HTML. Testi dei nomi presenti anche nel nome accessibile del collegamento. Vista mobile 390 px esaminata, nessun overflow. Funzione dettaglio invariata, sintassi valida.

Prima dell’intervento letta la versione pubblica: nella zona disponibile era visibile un annuncio con un solo alimento anche nel dettaglio; non è stato identificato né modificato il preciso annuncio a due articoli dell’utente. Il caso a due articoli è stato verificato con esempi locali simulati. Nessuna prenotazione reale e nessun dato di produzione creati per le prove.

## Base e perimetro
Base repository 318f0047741e2a9d2f94ee818aef824c9c845870. Cambiano soltanto app.js, index.html (cache items29) e stile. Nessun SQL eseguito, nessuna modifica a pubblicazione, autenticazione, storico, prenotazioni o protezioni. Logo ufficiale mantenuto.

## Pubblicazione
Esito finale registrato nella copia locale di consegna dopo controllo Pages.
