;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; wcheck-mode.el


;; Copyright (C) 2009 Teemu Likonen <tlikonen@iki.fi>
;;
;; LICENSE
;;
;; This program is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or (at
;; your option) any later version.
;;
;; This program is distributed in the hope that it will be useful, but
;; WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
;; General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs. If not, see <http://www.gnu.org/licenses/>.


;;; Muuttujat ja asetukset


(defvar wcheck-language-data
  '(("suomi" . ((program . "/usr/bin/enchant")
                (args . "-l -d fi_FI")))
    ("amerikanenglanti" . ((program . "/usr/bin/enchant")
                           (args . "-l -d en_US")))
    ("brittienglanti" . ((program . "/usr/bin/enchant")
                         (args . "-l -d en_GB")))
    ("cat" . ((program . "/bin/cat"))))
  "Tiedot eri kielistä")


(setq wcheck-language-data-defaults
      '((args . "")
        (face . wcheck-default-face)
        (syntax . text-mode-syntax-table)
        (regexp-start . "\\<'*")
        (regexp-word . "\\sw+?")
        (regexp-end . "'*\\>")
        (discard . "\\`'+\\'")))

(defvar wcheck-language
  (caar wcheck-language-data)
  "Oletuskieli on globaalissa muuttujassa, puskurikohtainen kieli
on puskurikohtaisessa muuttujassa. Tätä muuttujaa ei kannata
muokata suoraan; kieli kannattaa muuttaa komennolla
`\\[wcheck-change-language]'.")
(make-variable-buffer-local 'wcheck-language)

(setq wcheck-buffer-process-data nil)
(set (make-variable-buffer-local 'wcheck-returned-words) nil)

(defconst wcheck-process-name-prefix "wcheck/"
  "Oikolukuprosessien nimen etuliite. Tämä on vain ohjelman
sisäiseen käyttöön.")


(defface wcheck-default-face
  '((t (:underline "red")))
  "Tunnistamaton sana värjätään tällä värillä."
  :group 'Wcheck
  )


(defvar wcheck-mode-map
  (make-sparse-keymap)
  "Keymap for wcheck-mode")


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; Käyttäjän funktiot


(defun wcheck-change-language (language &optional global)
  "Vaihtaa oikoluvun kielen arvoksi LANGUAGE. Tavallisesti muutos
koskee vain nykyistä puskuri, mutta jos GLOBAL on
non-nil (interaktiivisesti prefix argument), niin vaihdetaan
oletuskieli."
  (interactive
   (let* ((comp (mapcar 'car wcheck-language-data))
          (default
            (if (member wcheck-language comp)
                wcheck-language
              (car comp))))
     (list (completing-read
            (format "Vaihda %s (%s): " (if current-prefix-arg
                                           "oletuskieli uusiin puskureihin"
                                         "nykyisen puskurin kieli")
                    default)
            comp nil t nil nil default)
           current-prefix-arg)))
  (if (not (stringp language))
      (error "Language must be a string")
    (if global
        (setq-default wcheck-language language)
      (setq wcheck-language language)
      (when wcheck-mode
        (wcheck-update-buffer-process-data (current-buffer) language)
        (wcheck-remove-overlays)))

    ;; Kieltä on muutettu, joten pyydetään päivitystä
    (wcheck-timer-request-for-update (current-buffer))))


(define-minor-mode wcheck-mode
  "Sanojen tarkistus, oikoluku."
  :init-value nil
  :lighter " Wck"
  :keymap wcheck-mode-map
  (if wcheck-mode
      ;; Oikoluku päälle mutta ensin pari tarkistusta:
      (cond
       ((minibufferp (current-buffer))
        ;; Kyseessä on minibuffer, joten ei kytketä päälle
        (setq wcheck-mode nil)
        (message "Ei voi kytkeä minibufferissa"))

       ((not (wcheck-language-valid-p wcheck-language))
        ;; Kieli ei ole toimiva
        (setq wcheck-mode nil)
        (message "Sopimaton kieli, ei kytketä oikolukua"))

       (t
        ;; Käynnistetään "oikoluku"

        ;; local hooks
        (add-hook 'kill-buffer-hook 'wcheck-hook-kill-buffer nil t)
        (add-hook 'window-scroll-functions 'wcheck-hook-window-scroll nil t)
        (add-hook 'after-change-functions 'wcheck-hook-after-change nil t)
        ;; (add-hook 'change-major-mode-hook
        ;;           'wcheck-hook-change-major-mode nil t)

        ;; global hooks
        (add-hook 'window-size-change-functions
                  'wcheck-hook-window-size-change)
        (add-hook 'window-configuration-change-hook
                  'wcheck-hook-window-configuration-change)

        (unless wcheck-buffer-process-data
          (setq wcheck-timer
                (run-with-idle-timer 0.5 t 'wcheck-timer-event)))

        ;; Seuraavan komennon PITÄÄ olla ajastimen käynnistämisen
        ;; jälkeen, koska ajastimen käynnistys katsoo muuttujasta
        ;; wcheck-buffer-process-data, että tarvitseeko ajastinta
        ;; ylipäätään käynnistää.
        (wcheck-update-buffer-process-data (current-buffer) wcheck-language)
        (wcheck-timer-request-for-update (current-buffer))))

    ;; Oikoluku pois
    (setq wcheck-returned-words nil)
    (wcheck-remove-overlays)
    (wcheck-update-buffer-process-data (current-buffer) nil)

    ;; local hooks
    (remove-hook 'kill-buffer-hook 'wcheck-hook-kill-buffer t)
    (remove-hook 'window-scroll-functions 'wcheck-hook-window-scroll t)
    (remove-hook 'after-change-functions 'wcheck-hook-after-change t)
    ;; (remove-hook 'change-major-mode-hook
    ;;              'wcheck-hook-change-major-mode)

    ;; global hooks
    (remove-hook 'window-size-change-functions
                 'wcheck-hook-window-size-change)
    (remove-hook 'window-configuration-change-hook
                 'wcheck-hook-window-configuration-change)))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; Ajastimet


(setq wcheck-timer nil
      wcheck-timer-update-requested nil)


(defun wcheck-timer-request-for-update (buffer)
  "Lisää puskurin BUFFER listaan, josta ajastin katsoo, mitä
puskureita pitää päivittää."
  (add-to-list 'wcheck-timer-update-requested buffer))


(defun wcheck-timer-no-need-for-update (buffer)
  "Poistaa puskurin päivitystä pyytäneiden puskurien listasta."
  (setq wcheck-timer-update-requested
        (delq buffer wcheck-timer-update-requested)))


(defun wcheck-timer-event ()
  ;; Käydään läpi kaikki puskurit, jotka ovat pyytäneet päivitystä.
  (dolist (buffer wcheck-timer-update-requested)
    ;; Mutta päivitetään tosiasiassa vain sellainen puskuri, joka on
    ;; nykyisessä ikkunassa.
    (when (eq buffer (window-buffer (selected-window)))
      ;; Poistetaan tämä puskuri listasta ja päivitetään.
      (wcheck-timer-no-need-for-update buffer)
      (wcheck-read-send-words-event buffer)
      (run-with-idle-timer 1 nil 'wcheck-mark-words-event
                           (selected-window)))))


(defun wcheck-read-send-words-event (buffer)
  "Funktio lukee sanat ikkunasta ja lähettää ne ulkoiselle
ohjelmalle. Tätä funktiota kutsutaan automaattisesti, kun
käyttäjä on keskeyttänyt tietyt toiminnot."
  (when (buffer-live-p buffer)
    (with-current-buffer buffer
      (if (not (wcheck-language-valid-p wcheck-language))
          (progn
            (wcheck-mode 0)
            (message "Kieli ei ole toimiva, sammutetaan oikoluku"))
        (setq wcheck-returned-words nil)
        (wcheck-send-words wcheck-language
                           (wcheck-read-words wcheck-language
                                              (selected-window)))))))


(defun wcheck-mark-words-event (window)
  "Funktio merkitsee sanat nykyisessä ikkunassa."
  (when (window-live-p window)
    (with-current-buffer (window-buffer window)
      (wcheck-remove-overlays)
      (wcheck-mark-words wcheck-language window wcheck-returned-words))))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; Koukut, joilla pyydetään oikoluvun päivitystä puskurille


(defun wcheck-hook-window-scroll (window window-start)
  "Ajetaan kun ikkunaa WINDOW on vieritetty."
  (with-current-buffer (window-buffer window)
    (when wcheck-mode
      (wcheck-timer-request-for-update (window-buffer window)))))


(defun wcheck-hook-window-size-change (frame)
  "Tämä ajetaan aina, kun ikkunan kokoa on muutettu."
  ;; Täällä pitäisi käydä FRAMEn kaikki ikkunat läpi (paitsi
  ;; minibuffer), katsoa, mikä puskuri missäkin ikkunassa on, ja jos
  ;; kyseisessä puskurissa on wcheck päällä, pyytää päivitystä.
  (walk-windows (function (lambda (window)
                            (when wcheck-mode
                              (wcheck-timer-request-for-update
                               (window-buffer window)))))
                'no-minibuf
                frame))


(defun wcheck-hook-window-configuration-change ()
  "Tämä ajetaan aina, kun ikkunan kokoa tai muita asetuksia on
muutettu."
  ;; Täällä pitäisi käydä nykyisen framen kaikki ikkunat läpi (paitsi
  ;; minibuffer), katsoa, mikä puskuri missäkin ikkunassa on, ja jos
  ;; kyseisessä puskurissa on wcheck päällä, pyytää päivitystä.
  (walk-windows (function (lambda (window)
                            (when wcheck-mode
                              (wcheck-timer-request-for-update
                               (window-buffer window)))))
                'no-minibuf
                'currentframe))


;; Pitää keksiä vielä koukku, joka päivittää ikkunan, mikäli käyttäjä
;; hyppää toiseen ikkunaan "C-x o" -komennolla.


(defun wcheck-hook-after-change (beg end len)
  "Ajetaan aina, kun puskuria on muokattu."
  ;; Tämä hook ajetaan aina siinä puskurissa, mitä muokattiin.
  (when wcheck-mode
    (wcheck-timer-request-for-update (current-buffer))))


(defun wcheck-hook-kill-buffer ()
  "Sammuttaa oikoluvun tämän puskurin osalta."
  (wcheck-mode 0))


(defun wcheck-hook-change-major-mode ()
  "Ajetaan ennen kuin käyttäjä vaihtaa major-tilaa. Tämä
sammuttaa oikoluvun tästä puskurista."
  (wcheck-mode 0))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; Prosessien käsittely


(defun wcheck-start-get-process (language)
  "Palauttaa oikolukuprosessin, joka käsittelee kieltä LANGUAGE.
Mikäli sellaista prosessia ei ennestään ole, käynnistetään."
  (when (wcheck-language-valid-p language)
    (let ((proc-name (concat wcheck-process-name-prefix language)))
      ;; Jos prosessi on jo ennestään olemassa, palautetaan se.
      (or (get-process proc-name)
          ;; Ei ole, joten luodaan uusi.
          (let ((program (wcheck-query-language-data language 'program))
                (args (split-string
                       (wcheck-query-language-data language 'args t)
                       "[ \t\n]+" t))
                (process-connection-type nil) ;Käytetään putkia
                proc)

            (when (file-executable-p program)
              (setq proc (apply 'start-process proc-name nil program args))
              ;; Asetetaan oikolukuprosessin tulosteenkäsittely kutsumaan
              ;; funktiota, joka tallentaa tulosteen eli tunnistamattomat
              ;; sanat muuttujaan wcheck-returned-words (buffer-local).
              (set-process-filter proc 'wcheck-receive-words)
              (when (wcheck-process-running-p language)
                proc)))))))


(defun wcheck-process-running-p (language)
  "Tarkistetaan, onko prosessi käynnissä."
  (eq 'run (process-status (concat wcheck-process-name-prefix language))))


(defun wcheck-end-process (language)
  "Poistaa oikolukuprosessin kielelle LANGUAGE, mikäli sellainen
on olemassa. Palautetaan poistettu prosessi tai nil, mikäli ei
tehty mitään."
  (let ((proc (get-process (concat wcheck-process-name-prefix
                                   language))))
    (when proc
      (delete-process proc)
      proc)))


(defun wcheck-update-buffer-process-data (buffer language)
  "Päivittää `wcheck-buffer-process-data' -muuttujan puskurin
BUFFER ja sitä vastaavan kielen LANGUAGE osalta. Mikäli LANGUAGE
on nil, poistetaan kyseinen puskuri listasta ja lopetetaan myös
kieltä vastaava prosessi, mikäli sitä ei enää mikään prosessi
tarvitse. Palautetaan muuttujan `wcheck-buffer-process-data'
uusi arvo tai nil, mikäli funktion parametrit eivät olleet
oikeanlaiset."

  ;; Tämä funktio voisi myös poistaa ne prosessit, joiden nimeen on
  ;; tullut <1>, <2> jne. siitä syystä, ettei olisi kahta samannimistä.
  ;; Tällaista ei pitäisi sattua mutta todellisuudessa kaikki on
  ;; mahdollista. Toinen vaihtoehto on luopua kokonaan miettimästä
  ;; prosessien nimiä ja tehdä sen sijaan alist, jossa on (KIELI .
  ;; PROSESSI) -elementtejä. Se tosin olisi yksi ajan tasalla pidettävä
  ;; lista lisää.

  (when (and (bufferp buffer)
             (or (stringp language)
                 (not language)))

    ;; Poistetaan listasta elementit, joiden cdr ei ole merkkijono
    (dolist (item wcheck-buffer-process-data)
      (unless (stringp (cdr item))
        (setq wcheck-buffer-process-data
              (delq item wcheck-buffer-process-data))))

    (let ((old-langs (mapcar 'cdr wcheck-buffer-process-data))
          new-langs)

      ;; Poistetaan listasta mahdolliset kuolleet puskurit sekä
      ;; minibufferit.
      (dolist (item wcheck-buffer-process-data)
        (when (or (not (buffer-live-p (car item)))
                  (minibufferp (car item)))
          (setq wcheck-buffer-process-data
                (delq item wcheck-buffer-process-data))))

      ;; Poistetaan tämä puskuri listasta
      (setq wcheck-buffer-process-data
            (assq-delete-all buffer wcheck-buffer-process-data))
      (if language
          ;; Lisätään puskurille uusi kieli
          (add-to-list 'wcheck-buffer-process-data
                       (cons buffer language))
        ;; Oikolukua on pyydetty sammutettavaksi, joten poistetaan se
        ;; päivitystä pyytäneiden prosessien listasta.
        (wcheck-timer-no-need-for-update buffer))

      ;; Poistetaan turhat prosessit
      (setq new-langs (mapcar 'cdr wcheck-buffer-process-data))
      (dolist (lang old-langs)
        (unless (member lang new-langs)
          (wcheck-end-process lang)))))

  (or wcheck-buffer-process-data
      (when wcheck-timer
        (cancel-timer wcheck-timer)
        (setq wcheck-timer nil))))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; Matalan tason apufunktioita


(defun wcheck-read-words (language window)
  "Palauttaa listan sanoista, jotka näkyvät ikkunassa IKKUNA."
  (when (window-live-p window)
    (with-selected-window window
      (save-excursion

        (let ((regexp (concat (wcheck-query-language-data
                               language 'regexp-start t) "\\("
                              (wcheck-query-language-data
                               language 'regexp-word t) "\\)"
                              (wcheck-query-language-data
                               language 'regexp-end t)))

              (syntax (eval (wcheck-query-language-data
                             language 'syntax t)))
              (w-end (window-end window 'update))
              (discard (wcheck-query-language-data
                        language 'discard t))
              words)

          (move-to-window-line 0)
          (beginning-of-line)
          (with-syntax-table syntax
            (while (< (point) w-end)
              (while (re-search-forward regexp (line-end-position) t)
                (unless (string-match discard
                                      (match-string-no-properties 1))
                  (add-to-list 'words
                               (match-string-no-properties 1)
                               'append))
                (goto-char (1+ (point))))
              (end-of-line)
              (vertical-motion 1)))
          words)))))


(defun wcheck-send-words (language wordlist)
  "Lähettää sanalistan WORDLIST oikolukuprosessille, joka
käsittelee kieltä LANGUAGE."
  (when (and (stringp language)
             (listp wordlist))
    ;; Noudetaan prosessi, joka hoitaa pyydetyn kielen.
    (let ((proc (wcheck-start-get-process language))
          string)
      ;; Tehdään sanalistasta merkkijono, yksi sana rivillään.
      (setq string (concat (mapconcat 'concat wordlist "\n")
                           "\n"))
      (process-send-string proc string)
      string)))


(defun wcheck-receive-words (process string)
  "Ottaa sanat vastaan oikolukuprosessilta."
  (setq wcheck-returned-words (append wcheck-returned-words
                                      (split-string string "\n+" t))))


(defun wcheck-mark-words (language window wordlist)
  "Merkkaa listassa WORDLIST listatut sanat ikkunassa WINDOW."
  (when (window-live-p window)
    (with-selected-window window
      (save-excursion
        (let ((w-start (window-start window))
              (w-end (window-end window 'update))
              (r-start (wcheck-query-language-data language 'regexp-start t))
              (r-end (wcheck-query-language-data language 'regexp-end t))
              (syntax (eval (wcheck-query-language-data language 'syntax t)))
              (case-fold-search nil))
          (with-syntax-table syntax
            (dolist (word wordlist)
              (setq word (regexp-quote word))
              (goto-char w-start)
              (while (re-search-forward
                      (concat r-start "\\(" word "\\)" r-end)
                      w-end t)
                (wcheck-make-overlay language window
                                     (match-beginning 1)
                                     (match-end 1))))))))))


(defun wcheck-query-language-data (language key &optional default)
  "Palauttaa pyydetyn tiedon kielitietokannasta tai mahdollisesti
oletusarvon."
  (or (cdr (assq key (cdr (assoc language wcheck-language-data))))
      (when default
        (cdr (assq key wcheck-language-data-defaults)))))


(defun wcheck-language-valid-p (language)
  "Tarkistaa, onko LANGUAGE olemassa ja onko sille määritelty
ulkoista ohjelmaa. Palauttaa t tai nil."
  ;; Löytyykö kieltä?
  (if (member language (mapcar 'car wcheck-language-data))
    ;; Löytyy. Löytyykö sille määriteltyä ohjelmaa? Huom, tämä ei vielä
    ;; testaa, onko kyseinen merkkijono ajettava ohjelma.
      (if (stringp (wcheck-query-language-data language 'program))
          t)))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; Overlay


(defun wcheck-make-overlay (language window beg end)
  (let ((overlay (make-overlay beg end))
        (face (wcheck-query-language-data language 'face t)))
    (dolist (prop `((wcheck-mode . t)
                    (window . ,window)
                    (face . ,face)
                    (modification-hooks . (wcheck-remove-overlay-word))
                    (insert-in-front-hooks . (wcheck-remove-overlay-word))
                    (insert-behind-hooks . (wcheck-remove-overlay-word))
                    (evaporate . t)))
      (overlay-put overlay (car prop) (cdr prop)))))


(defun wcheck-remove-overlays (&optional beg end)
  (remove-overlays beg end 'wcheck-mode t))


(defun wcheck-remove-overlay-word (overlay after beg end &optional len)
  "Poistaa overlayn, jonka osoittamaa sanaa muokataan."
  (unless after
    ;; Juuri ennen kuin muokkaus alkaa poistetaan overlay.
    (delete-overlay overlay)))


(provide 'wcheck-mode)
