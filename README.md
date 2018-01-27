# Inkrementelles Backup
***
Legt ein inkrementelles Backup auf einem Remote-Host an.     

**Version:** 1.0

***
## ToDo
1. Die Verzeichnisse **/mnt/daily** & **/mnt/rotate** erzeugen.  
_Wenn andere Verzeichnisse verwendet werden sollen, die Zeilen 24 & 27 im Script aendern!_
2. Im **Home-Verzeichnis** die Datei **rotate_key** erzeugen und das Passwort einfuegen.  
_Wenn ein anderes Verzeichnis oder eine andere Datei verwendet werden sollen, die Zeile 108 im Script aendern!_
3. Die Pakete **sshfs**, **curlftpfs** und **heirloom-mailx** _(oder einen vergleichbaren MUA)_ installieren.
4. Die Variablen im Script, in den **Zeilen 21-23 & 26**, anpassen, ggf. auch **Zeile 29**.

***
## Bugs und/oder Fixes bitte an:
**Autor:** freakonomic

**Mail:** [info@freakonomic.de](mailto:info@freakonomic.de)