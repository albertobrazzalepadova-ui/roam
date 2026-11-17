# Identità Roam

Logo vettoriale originale: una R costruita come un percorso continuo con freccia di direzione.

- Sfondo: bianco.
- Accento: rosso corallo, RGB 0.88 / 0.10 / 0.19.
- Superfici: grigio chiarissimo, RGB 0.97 / 0.97 / 0.98.
- Tipografia: San Francisco di sistema con titoli ampi e gerarchie native.
- Componenti: NavigationStack, tab bar di sistema, SF Symbols, PhotosPicker, mappe e moduli nativi.

`roam-logo.svg` è il master vettoriale. `render-icon.swift` genera un PNG opaco 1024×1024 per l'asset AppIcon:

```sh
swiftc -module-cache-path /tmp/roam-swift-cache design/render-icon.swift -o /tmp/roam-icon-render
/tmp/roam-icon-render "$PWD/ios/Roam/Assets.xcassets/AppIcon.appiconset/icon-1024.png"
```

Il marchio nell'app è disegnato da `RoamMark` in SwiftUI, così rimane nitido a ogni dimensione.

## Logo immagine ed effetto Wow

`roam-logo-image.png` è il nuovo logo raster generato con il tool integrato image_gen; il prompt esatto è in `logo-image-prompt.txt`. È usato nell'assistente e, esportato a 1024 px, nell'icona iOS. Il precedente SVG rimane una variante vettoriale distinta.

`roam.ico` contiene sei immagini PNG, a 16, 32, 48, 64, 128 e 256 px. È destinato a Windows/web; iOS usa l'asset AppIcon PNG.

Conversione ripetibile:

```sh
swiftc -module-cache-path /tmp/roam-swift-cache design/export-logo.swift -o /tmp/roam-export
/tmp/roam-export "$PWD/design/roam-logo-image.png" "$PWD/design/roam.ico" "$PWD/ios/Roam/Assets.xcassets/AppIcon.appiconset/icon-1024.png"
```

Le intestazioni native usano sfondo rosso e testo bianco. La scheda esplorazione include percorso animato, bussola fluttuante e inclinazione al trascinamento. Le animazioni rispettano Riduci movimento; i filtri danno un feedback aptico di selezione.

## Intestazioni uniformi

Esplora, Viaggi, Assistente e Profilo usano tutte il titolo nativo inline, con la stessa altezza della barra e font 20 pt bold. L'aspetto opaco rosso è condiviso tra standard, scroll edge e compact: comprende l'area della status bar e non cambia altezza scorrendo la pagina. Le altezze della safe area restano quelle previste dal dispositivo.

## Mappa e icone dei luoghi

La home integra una mappa MapKit interattiva in un pannello bianco, con intestazione “Il tuo radar”, controlli rossi, legenda delle categorie e scheda del punto selezionato. I filtri agiscono sia sui marker sia sull'elenco. La cartografia nativa usa lo stile standard attenuato, senza POI di sistema, per valorizzare i segnaposto personalizzati; l'attribuzione cartografica resta visibile. La selezione sparisce se il luogo viene escluso da un filtro. Il pulsante posizione ricentra la mappa e rispetta Riduci movimento.

Le tre icone sono SVG originali, senza dipendenze da librerie di icone esterne:
- `poi/RoamAttraction.svg`: edificio monumentale.
- `poi/RoamCafe.svg`: tazza con vapore.
- `poi/RoamShop.svg`: borsa con manico.

Gli stessi SVG sono inclusi nel catalogo asset Xcode come immagini vettoriali template, usate nei marker, nelle schede e nella legenda. La mappa dettaglio mantiene lo stesso stile. La mappa compare solo con coordinate disponibili; non vengono inseriti punti dimostrativi.

## Finitura nativa iPhone

I luoghi si aprono in sheet SwiftUI condivise tra mappa ed elenco, con detent medio/grande, maniglia di trascinamento e pulsante Fine. La home usa gerarchie tipografiche di sistema, righe con separatori e icone SVG; il filtro selezionato scorre con matchedGeometryEffect. Feedback aptico nativo accompagna categorie e selezione mappa. Le righe hanno una lieve transizione di scala/opacità durante lo scorrimento, disattivata con Riduci movimento.

Le anteprime sulla mappa e il campo messaggio usano regularMaterial. Bussola e scala sono controlli MapKit nativi. I contatori usano numericText. Le intestazioni rosse uniformi e la tab bar di sistema rimangono comuni alle quattro sezioni. La creazione di un viaggio si apre in un foglio nativo; in chat il testo è selezionabile e la tastiera può essere chiusa scorrendo.

## Home con mappa protagonista

La mappa è il primo elemento della home, a tutta larghezza, alta 470 pt, con luogo, meteo e conteggio dei luoghi in un pannello regularMaterial. Profilo e filtri seguono la mappa. La vista iniziale usa una camera inclinata a 45° con elevazione realistica dove supportata dalla cartografia. I controlli permettono di ricentrare, alternare 2D/3D e aprire una mappa a schermo intero. La selezione di un luogo sposta la camera verso il marker. Con Riduci movimento i cambi camera sono immediati. Nessuna animazione cambia la posizione reale o introduce punti dimostrativi.

## UX a schede dal riferimento

La mappa protagonista resta invariata. Sotto la mappa, il contenuto usa schede bianche su fondo grigio freddo chiaro con accenti rossi: profilo con statistiche effettive, campo ricerca a pillola, categorie e prossimo viaggio (solo se presente). La ricerca per nome, categoria e indirizzo filtra insieme elenco e marker, e mostra uno stato vuoto dedicato quando non ci sono corrispondenze. Il prossimo viaggio rispetta la data locale del dispositivo.

Profilo e Viaggi usano il medesimo fondo; la chat ha una scheda intestazione e bolle rosse per l'utente, bianche per l'assistente. Nessuna statistica o attività simulata è aggiunta al dashboard.

## Barre leggere e home trasparente

Questa revisione sostituisce le precedenti intestazioni rosse. La home nasconde la navigation bar e porta la mappa fino al bordo superiore. Il logo piccolo, il luogo e il meteo sono in un pannello sospeso regularMaterial; i controlli usano lo stesso materiale. La safe area è misurata con GeometryReader per tenere i controlli sotto status bar e fotocamera.

Viaggi, Assistente, Profilo, moduli e dettagli usano barre native chiare con titoli neri e azioni rosse. Standard, scroll-edge e compact condividono lo stesso aspetto; la tab bar resta quella di sistema.

## Copertine senza mappe

Le schede usano foto della community, anteprime Look Around oppure le tre immagini generate in `place-covers/`. Le immagini AI sono esplicitamente illustrative di categoria, non ricostruzioni certificate del luogo effettivo, e sono etichettate nell'app. Nessun MKMapSnapshotter viene usato nelle copertine. La mappa principale e quella nel dettaglio restano interattive. I prompt e la modalità built-in image_gen sono documentati in `place-covers/prompts.md`.

## Direzione editoriale

Questa revisione sostituisce il sistema di schede fotografiche verticali con una galleria orizzontale a scatti. Copertine da 360 pt, titolo sovrapposto bianco, sfumatura di contrasto e badge rosso; le etichette delle immagini AI restano visibili. Le categorie sono sempre accessibili, mentre la ricerca si apre dal pulsante filtri. Scorrimento e pressione hanno animazioni leggere, disattivate con Riduci movimento.

Lo sfondo diventa un bianco caldo quasi neutro. La gerarchia usa titoli rounded più grandi e meno contenitori. Viaggi ha schede itinerario in stile biglietto con date e note reali; l'assistente ha un'apertura tipografica e tre suggerimenti che inviano richieste effettive. La mappa conserva impostazione e controlli approvati. Foto e immagini AI esistenti vengono riutilizzate, senza generare ulteriori luoghi o statistiche.

## Monumenti 3D sulla mappa

Primo monumento: Torre Eiffel, coordinate 48.85837 / 2.294481. Il menu Monumenti 3D nei controlli mappa porta la camera a Parigi; il pulsante posizione torna alla zona dell'utente. L'anteprima viene etichettata e non sostituisce posizione o meteo con dati di Parigi.

Il modello è originale, creato con geometrie SceneKit (travi, controventature, piattaforme e antenna), senza asset esterni. `EiffelMapModel` viene renderizzato con sfondo trasparente in un'Annotation MapKit, ancorata al monumento. Camera del modello e dimensione reagiscono a heading, pitch e distanza della mappa. In 2D torna il segnaposto; il dettaglio e i commenti usano un identificativo persistente dedicato.

È un segnaposto 3D illustrativo: la geometria non è fusa nel terreno MapKit, non ha scala metrica garantita né occlusione con gli edifici della cartografia. Il catalogo dei monumenti contiene per ora solo la Torre Eiffel. I luoghi locali ordinari mantengono i segnaposto SVG; la Torre Eiffel non viene inserita artificialmente nei risultati entro 5 km.

## Catalogo ampliato a 16 monumenti

Questa revisione supera il primo esempio della Torre Eiffel. I cataloghi sincronizzati sono `backend/landmarks.json` e l'asset iOS `Landmarks.dataset/catalog.json`; un test verifica che coincidano. Il menu Monumenti 3D è organizzato per città.

Sono inclusi: Torre Eiffel, Colosseo, Torre di Pisa, Ponte di Rialto, Basilica e Campanile di San Marco, Duomo di Milano, Duomo di Firenze, Arena di Verona, Mole Antonelliana, Big Ben, Piramide del Louvre, Porta di Brandeburgo, Sagrada Família, Torre di Belém e Arco di Trionfo.

I modelli procedurali originali sono rappresentazioni illustrative basate su forme architettoniche riconoscibili: traliccio, anello di arcate, torre inclinata, ponte, cupole, guglie, campanile, torre con orologio, piramide, porta colonnata e fortificazione. I modelli non selezionati sono più piccoli per ridurre le sovrapposizioni. Restano annotazioni 3D senza fusione nel terreno o occlusione con gli edifici MapKit. I luoghi locali continuano a essere ricercati nella zona reale dell'utente.

## Rimozione dei modelli illustrativi

Su richiesta dell’utente, i modelli 3D dei monumenti e il menu delle anteprime sono stati rimossi dalla homepage e dai dettagli. Tutti i luoghi trovati usano i normali segnaposto Roam, inclusi i monumenti. Resta disponibile la prospettiva nativa 2D/3D di MapKit. Le sezioni precedenti descrivono revisioni storiche.

## Feed legato all’area visibile e foto web

Al termine di zoom o spostamento, la ricerca aggiorna progressivamente segnaposto e feed con i luoghi nell’area visibile. Le distanze restano dalla posizione dell’utente. Le richieste superate vengono annullate e le aree già cercate restano in cache per dieci minuti. La ricerca può essere disabilitata dal profilo.

Le copertine cercano più candidati fotografici su Commons, con ricerca alternativa per i nomi e recupero delle immagini degli articoli Wikipedia quando le coordinate dell’articolo corrispondono al luogo (entro 1 km). Alle API foto vengono inviati i nomi, senza coordinate dell’utente. I metadati Commons forniscono licenza e autore; l’app prova candidati alternativi se il primo URL non si carica. La disponibilità di immagini per tutti i negozi non è garantita.

## Feed social di viaggio

Esplora ha una mappa più compatta ed espandibile, seguita dal feed misto di esperienze e schede dei luoghi. I filtri Vicino a te, Sulla mappa e Salvati distinguono ricerca locale, viewport e raccolta personale. Le esperienze hanno foto caricata dall’utente, nome autore, data, valutazione, testo, commenti dedicati e indicazioni Apple Maps. Le schede di scoperta sono marcate come tali; nessuna attività social viene inventata.

Il compositore associa una foto JPEG e un racconto a uno dei luoghi caricati. Post, salvataggi e conversazioni persistono in SQLite. Le recensioni dei luoghi già presenti vengono esposte una sola volta nel feed tramite un identificativo stabile; le loro foto di copertina restano foto del luogo con fonte esplicita. Il feed ha pagine da 20 post. Questa versione mantiene il profilo personale condiviso del backend esistente, senza account o identità separate.

## Feed nella scheda centrale

La barra inferiore ha cinque pagine: Esplora, Viaggi, Feed, Assistente e Profilo. Feed è la terza scheda e contiene solo post, compositore, commenti e salvataggi; Esplora torna a mostrare mappa e schede dei luoghi. Il filtro Sulla mappa del Feed usa l’ultima area esplorata nella homepage, mentre Vicino a te usa i luoghi nei dintorni della posizione.
