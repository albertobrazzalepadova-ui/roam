# Contenuti dimostrativi Roam

Immagini generate con AI: 12 scene illustrative e 14 ritratti di persone fittizie.
Non sono fotografie documentarie delle attività o dei luoghi citati.
I file sono locali: il feed non dipende da servizi di immagini esterni.

Da backend: `python seed.py` aggiorna 14 profili, 20 post fotografici,
53 recensioni, commenti e viaggi demo. Ogni esecuzione salva prima una copia
SQLite `roam.db.bak-demo-*`. `python seed.py --remove` rimuove i dati demo.
Il profilo personale e i record senza prefisso demo vengono conservati.

Nel feed i contenuti demo hanno un'etichetta. Toccare un avatar demo apre
nome, ritratto e bio. Occorre ricompilare l'app iOS per vedere queste novità.
