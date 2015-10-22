(ql:quickload '(usocket cl-json babel))

;; Define these in file "cian-lisp-configs.lisp" in the path reported by sbcl:
;;
;; (defparameter *server-host* "server")
;; (defparameter *server-port* 4567)
;; (defparameter *game-id* "own-game-name")
;; (defparameter *own-hostname* "10.101.101.156")

(defparameter *server-host* nil)
(defparameter *server-port* nil)
(defparameter *game-id* nil)
(defparameter *own-hostname* nil)
(defparameter *skip-auto-start* nil)

(defparameter *skip-auto-start* nil)

(defparameter *debug* nil)
(defparameter *player-name* "Cian Lisp")
(defparameter *player-color* "red")
(defparameter *run-client* t)

(defparameter *connection-id* nil)
(defparameter *listen-socket* nil)


(load (merge-pathnames "cian-lisp-configs.lisp" *default-pathname-defaults*))


(defun alist-to-json-octets (an-alist)
  (let ((json-string (json:encode-json-alist-to-string an-alist)))
    (if *debug* (format t "JSON string ~A~%" json-string))
    (babel:string-to-octets json-string :encoding :utf-8)))

(defun json-octets-to-alist (octets) 
  (let ((a-the-json-string (babel:octets-to-string octets :encoding :utf-8)))
    (json:decode-json-from-string a-the-json-string)))

(defun ip-addr-array-to-string (address-array) (format nil "~{~A~^.~}" (coerce address-array 'list)))

(defun send-alist-to-socket (list-to-send socket)
  (let* ((octet-array (alist-to-json-octets list-to-send))
         (length-of-octet-array (array-total-size octet-array)))
    (usocket:socket-send socket octet-array length-of-octet-array)))

(defun read-and-parse ()
  (if *debug* (format t "Blocking for read...~%"))
  (let* ((return-buffer (usocket:socket-receive *listen-socket* nil 65507))
         (return-val (json-octets-to-alist return-buffer)))
    (if *debug* (format t "~A" return-val))
    return-val))

(defun extract-or-default (alist key default)
  (let ((the-value (cdr (assoc key alist))))
    (if the-value the-value default)))

(defun join-game (socket)
  (format t "join game")
  (send-alist-to-socket 
   (list (cons "connection-id" *connection-id*)
         (cons "type" 'join)
         (cons "name" *player-name*)
         (cons "color" *player-color*)
         (cons "game-id" *game-id*)
         (cons "players" (list
                          (list (cons 'number 1) (cons 'name "Antero"))
                          (list (cons 'number 2) (cons 'name "Bob"))
                          (list (cons 'number 3) (cons 'name "Charles"))
                          (list (cons 'number 4) (cons 'name "David"))
                          (list (cons 'number 5) (cons 'name "Esko"))
                          (list (cons 'number 6) (cons 'name "Frank"))
                          (list (cons 'number 7) (cons 'name "Gilles"))
                          (list (cons 'number 8) (cons 'name "Hank"))
                          (list (cons 'number 9) (cons 'name "Ilpo"))
                          (list (cons 'number 10) (cons 'name "Jack"))
                          (list (cons 'number 11) (cons 'name "Kevin")))))
   socket))

(defun read-welcome-msg (socket)
  (let* ((welcome-msg-alist (read-and-parse))
         (connect-address (extract-or-default welcome-msg-alist :address
                                              *server-host*))
         (connect-port (extract-or-default welcome-msg-alist :port
                                           *server-port*)))
    (defparameter *connection-id* (cdr (assoc :connection-id welcome-msg-alist)))
    (format t "C: Got welcome msg foo ~A~%" welcome-msg-alist)
    (if (or (cdr (assoc :address welcome-msg-alist)) (cdr (assoc :port welcome-msg-alist)))
        (progn
          (let ((local-port (usocket:get-local-port socket))) 
            (usocket:socket-close socket)
            (usocket:socket-connect connect-address connect-port
                                    :protocol :datagram :element-type '(unsigned-byte 8)
                                    :local-port local-port)))
        socket)))

(defun handle-ping (socket)
  (format t ".")
  (send-alist-to-socket 
   (list (cons 'type 'pong) (cons "connection-id" *connection-id*))
   socket))

(defun handle-game (socket)
  (loop while t do 
       (let* ((packet (read-and-parse)) (msg-type (cdr (assoc :type packet))))
         (cond 
           ((equal "ping" msg-type) (handle-ping socket))
           ((equal "match-start" msg-type)
            (progn 
              (set-game-values packet))) ;; TODO: Implement it!
           ((equal "tick" msg-type) (match-tick packet socket))
           ((equal "match-end" msg-type) (loop-finish))
           ((equal "action-error" msg-type) (format t "Action error: ~A~%" packet))
           (t (format t "Unknown message in match! ~A~%" msg-type))))))

(defun run-client-inner (socket)
  (if *debug* (format t "C: Receiving data~%") )
  (let* ((server-msg (read-and-parse))
         (msg-type (cdr (assoc :type server-msg))))
    (if *debug* (format t "C: type was ~A~%" msg-type))
    (cond
      ((equal "ping" msg-type) (handle-ping socket))
      ((equal "join-ok" msg-type) (handle-game socket))
      ((equal "join-error" msg-type) (format t "FAILED TO JOIN GAME! reason: ~A~%" (extract-or-default server-msg :description "unknown")))
      (t (format t "C: Got unknown obj: ~A~%" server-msg)))))

(defun create-client ()
  (let 
      ((listen-socket (usocket:socket-connect nil nil :protocol :datagram :local-host *own-hostname* :element-type '(unsigned-byte 8)))
       (socket (usocket:socket-connect *server-host* *server-port*
				       :protocol :datagram
				       :element-type '(unsigned-byte 8)))
       (*player-name* (format nil "~A - ~A" *player-name* (random 1000 (make-random-state t)))))
    (unwind-protect
	 (progn
	   (defparameter *listen-socket* listen-socket)
	   (format t "C: Sending data~%")
           (send-alist-to-socket 
            (list (cons 'type 'connect) (cons 'address (ip-addr-array-to-string (usocket:get-local-address socket))) (cons 'port (usocket:get-local-port listen-socket)))
            socket)
           (let ((game-socket (read-welcome-msg socket)))
             (join-game game-socket)
             (run-client-inner game-socket)
             (format t "Good game!")
             t)
           (usocket:socket-close socket)))))


(if (not *skip-auto-start*)
    (create-client))

(defun c ()
  (create-client))
