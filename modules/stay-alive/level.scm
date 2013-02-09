;; Updated!
(define-module (stay-alive level)
  #:use-module (shelf shelf)
  #:use-module (shelf shelf-util)
  #:use-module (stay-alive extensions)
  #:use-module (stay-alive shared)
  #:use-module (stay-alive util)
  #:use-module (stay-alive ncurses-interface)
  #:use-module (srfi srfi-1)
  #:use-module (ice-9 receive)
  #:use-module (stay-alive game)
  #:use-module (stay-alive timer)
  #:use-module (stay-alive delta-queue)
  #:export (Level))

(define-object Level
  (initialize! (method (dungeon depth top? bottom?)
		 (set! ($ this 'dungeon) (object-reference dungeon))
		 (set! ($ this 'depth) depth)
		 (set! ($ this 'bottom?) bottom?)
		 (set! ($ this 'top?) top?)
		 (set! ($ this 'last-entered) (the-clock))
		 (set! ($ this 'opacity) (make-bitvector (* 20 80) #f))
		 (set! ($ this 'items) '())
		 (set! ($ this 'squares) (make-array *unspecified* 20 80))
		 (set! ($ this 'agent-queue) (instance DeltaQueue))
		 (set! ($ this 'player-memory) 
		       (make-array *unspecified* ($ this 'get-rows) ($ this 'get-cols)))))
  (update-weights! 
   (method (weight-function) 
     (let* ((squares ($ this 'squares))
	    (dimensions (list ($ this 'get-rows) ($ this 'get-cols)))
	    (weights (make-array *unspecified* (car dimensions) (cadr dimensions))))
       (for-each-index 
	(car dimensions)
	(cadr dimensions)
	(lambda (row col)
	  (array-set! weights (weight-function (array-ref squares row col)) row col)))
       (for-each 
	(lambda (agent) (array-set! weights 10000 ($ agent 'row) ($ agent 'col)))
	($ this 'agents))
       (set! ($ this 'weights) weights))))
  (get-player (method () (find ($ applicator 'player?) ($ this 'agents))))
  (paths-to-agent 
   (method (agent) (dijkstra ($ this 'weights) `(,($ agent 'row) ,($ agent 'col)) #t)))
  (has-memory-of? 
   (method (row col) ($ ($ this `(player-memory (,row ,col))) 'tile #:def #f)))
  (clear-agents-from-location! 
   (method (location)  
     (let ((agent ($ this 'agent-at location)))
       (if agent ($ agent 'move-to-empty-location this)))))
  (find-location (method (proc)
		   (let row-look ((row (- ($ this 'get-rows) 1)))
		     (let col-look ((col (- ($ this 'get-cols) 1)))
		       (let ((square ($ this `(squares (,row ,col)))))
			 (cond 
			  ((proc square) (list row col))
			  ((> col 0) (col-look (- col 1)))
			  ((> row 0) (row-look (- row 1)))
			  (else #f)))))))
  (random-location 
   (method (proc) 
     (let try-location 
	 ((row (random ($ this 'get-rows))) (col (random ($ this 'get-cols))))
       (if (proc ($ this `(squares (,row ,col))) (list row col))
	   (list row col)
	   (try-location (random ($ this 'get-rows)) (random ($ this 'get-cols)))))))
  (find-up-stairs-location
   (method () ($ this 'find-location (lambda (square) ($ square 'up-stairs? #:def #f)))))
  (find-down-stairs-location 
   (method () ($ this 'find-location (lambda (square) ($ square 'down-stairs? #:def #f)))))
  (insert-agent 
   (method (agent #:optional location) 
     (let ((new-location 
	    (or
	     location
	     (case ($ agent 'status)
	       ((descending-stairs) ($ this 'find-up-stairs-location))
	       ((ascending-stairs) ($ this 'find-down-stairs-location))
	       (else ($ this 'random-location 
			   (lambda (square location) 
			     (and
			      (not ($ this 'contains-agent? location))
			      ($ square 'can-agent-enter? agent)))))))))
       ($ this 'clear-agents-from-location! new-location)
       ($ agent 'set-location! new-location)
       (if ($ agent 'player?) 
	   (set! ($ this 'paths-to-player) ($ this 'paths-to-agent agent)))
       ($ ($ this 'agent-queue) 'enqueue! agent ($ agent 'speed))
       ($ agent 'on-enter-square this new-location))))
  (remember 
   (method (row col)
     (let ((memory ($ this `(player-memory (,row ,col))))
	   (square ($ this `(squares (,row ,col))))
	   (items ($ this 'items-at (list row col))))
       (set! ($ memory 'tile) ($ square 'tile))
       (set! ($ memory 'description) ($ square 'description))
       (set! ($ memory 'items) 
	     (if (null? items) 
		 #f 
		 (map (lambda (item) 
			`((symbol . ,($ item 'symbol)) 
			  (description . ,($ item 'describe-inventory)))) 
		      items))))))
  (prepare-for! 
   (method (agent)
     (let* ((light-sources
	     (append (map 
		      (lambda (item) (cons ($ item 'location) ($ item 'light-radius))) 
		      (filter (lambda (item) ($ item 'lit? #:def #f)) ($ this 'items)))
		     (fold (lambda (agent els)
			     (append els 
				     (map 
				      (lambda (item) 
					(cons ($ agent 'location) ($ item 'light-radius)))
				      (filter 
				       (lambda (item) 
					 ($ item #:def #f 'lit?)) ($ agent 'items))))) 
			   '() 
			   ($ this 'agents))))
	    (see-bits 
	     (see-level 
	      ($ this 'opacity) 
	      light-sources 80 ($ agent 'location) (array-dimensions ($ this 'squares)))))
       (set! ($ this 'lighting) (car see-bits))
       (if (not ($ agent 'blind? #:def #f)) 					       
	   (set! ($ this 'visibility) (cdr see-bits))
	   (set! ($ this 'visibility) (make-bitvector (* 20 80) #f))))))
  (describe 
   (method (agent location)
     (clear-message)
     (if (bitvector-ref 
	  ($ this 'visibility) 
	  (row-major (car location) (cadr location) ($ this 'get-cols)))
	 (let ((items ($ this 'items-at location))
	       (agent-at ($ this 'agent-at location)))
	   (if agent-at
	       (begin
		 (message (format #f "~a (/ for more info)" ($ agent-at 'describe)))
		 (set! ($ agent 'follow-up-command) 
		       (enclose ((text ($ agent-at 'describe-long))) ()
				(message text)
				#f)))
	       (if (not (null? items))
		   (display-items 
		    items "Items here: " "No items here" player-confirm-callback)
		   (message ($ ($ this `(squares ,location)) 'description)))))
	 (let* ((memory ($ this `(player-memory ,location)))
		(memory-description ($ memory 'description))
		(memory-items ($ memory 'items)))
	   (if memory-items
	       (display-memory-items memory-items player-confirm-callback)
	       (if memory-description
		   (message (format #f "~a (remembered)" memory-description))
		   (message "unknown square")))))))
  (get-rows (method () (car (array-dimensions ($ this 'squares)))))
  (get-cols (method () (cadr (array-dimensions ($ this 'squares)))))
  (agent-at 
   (method (location) 
     (find (lambda (agent) (equal? location ($ agent 'location))) ($ this 'agents))))
  (next-turn 
   (method (player)
     (receive (agent time) 
	 ($ ($ this 'agent-queue) 'dequeue!)
       ($ ($ this 'agent-queue) 'enqueue! agent ($ agent 'speed))
       ($ this 'pass-time time)
       ($ this 'prepare-for! agent)
       (refresh-level-view this agent)
       (while (not ($ agent 'take-turn ($ this 'paths-to-player) player this)) 
	 (refresh-level-view this agent))
       (agent 'clear-interrupt!)
       (if (agent 'player?)
	   (begin
	     (set! ($ this 'paths-to-player) ($ this 'paths-to-agent agent))
	     (bitvector-foreach-row-major 
	      (lambda (row col) ($ this 'remember row col))
	      ($ this 'visibility)
	      ($ this 'get-cols)))))))
  (items-at 
   (method (location) 
     (let ((items 
	    (filter 
	     (lambda (item) 
	       (and (= (car ($ item 'location)) (car location)) 
		    (= (cadr ($ item 'location)) (cadr location)))) 
	     ($ this 'items))))
       (for-each 
	(lambda (item letter-number) 
	  (set! ($ item 'letter) (integer->char (+ letter-number 97)))) 
	items (iota (length items)))
       items)))
  (add-item! 
   (method (item) 
     (set! ($ this 'items) (append ($ this 'items) (list item)))))
  (set-square! 
   (method (row col square)
     (if ($ this 'weights #:def #f)					 
	 (set! ($ this `(weights (,row ,col))) ($ square 'weight)))
     (set! ($ this `(squares (,row ,col))) square)
     (bitvector-set! ($ this 'opacity) 
		     (row-major row col ($ this 'get-cols))
		     ($ square 'opaque?))))
  (remove-item! wrap-remove-item)
  (pass-time 
   (method (time)
     (letrec* 
	 ((clock (the-clock))
	  (tick-timers 
	   (lambda* (thing #:optional agent)
	     (set! ($ thing 'timers)
		   (fold (lambda (timer rest) 
			   (if ($ timer 'tick this) (cons timer rest) rest))
			 '() ($ thing 'timers #:def '())))))
	  (for-all-items
	   (lambda (thing-with-items)
	     (for-each 
	      (lambda (item)
		(for-all-items item)
		(tick-timers item thing-with-items))
	      ($ thing-with-items 'items #:def '()))))
	  (do-every-1000 
	   (lambda (proc start duration)
	     (let ((initial (- 1000 (remainder start 1000))))
	       (if (>= duration initial) 
		   (begin
		     (proc)
		     (for-each (lambda (n) (proc)) 
			       (iota (quotient (- duration initial) 1000))))))))
	  (update-timers 
	   (lambda () 
	     (for-all-items this)
	     (for-each (lambda (agent)
			 (for-all-items agent)
			 (tick-timers agent))
		       ($ this 'agents))
	     (tick-timers this))))
       (do-every-1000 update-timers clock time)
       (the-clock time))))
  (agents (method () ($ ($ this 'agent-queue) 'get-members)))
  (contains-agent? 
   (method (location)
     (find (lambda (agent) 
	     (equal? ($ agent 'location) location)) ($ this 'agents))))
  (can-agent-enter-location? 
   (method (agent location) 
     (and
      (not ($ this 'contains-agent? location))
      ($ ($ this (list 'squares location)) 'can-agent-enter? agent)))))
