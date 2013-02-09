;; Updated!
(define-module (stay-alive agent)
  #:use-module (shelf shelf)
  #:use-module (shelf shelf-util)
  #:use-module (stay-alive util)
  #:use-module (stay-alive ncurses-interface)
  #:use-module (stay-alive lang)
  #:use-module (stay-alive shared)
  #:use-module (stay-alive square)
  #:use-module (stay-alive body)
  #:use-module (stay-alive game)
  #:export (move-agent-direction-long move-agent-direction))

(define (move-agent level agent new-location)
  (cond ((and (within-dimensions? new-location ($ level 'squares)) 
	      ($ level 'can-agent-enter-location? agent new-location)
	      ($ ($ level (cons 'squares (list new-location))) 'can-agent-enter? agent))
	 ($ agent 'on-leave-square level ($ agent 'location))
	 (set! ($ agent 'row) (car new-location))
	 (set! ($ agent 'col) (cadr new-location))
	 ($ agent 'on-enter-square level new-location)
	 #t)
	((and ($ agent 'can-open-doors?) 
	      (not ($ agent #:def #f 'saved-command)) 	      
	      ($ ($ level (cons 'squares (list new-location))) #:def #f 'closed-door?))
	 ($ level 'set-square! (car new-location) (cadr new-location) (instance OpenDoor))
	 (message-player 
	  level #t
	  (lambda (visibility)
	    (cond
	     ((bitvector-ref visibility (row-major 
					 (car ($ agent 'location))
					 (cadr ($ agent 'location)) ($ level 'get-cols)))
	      ($ level 'remember (car new-location) (cadr new-location))
	      (format #f "~a ~a the door." 
		      (capitalize ($ agent 'describe-definite)) 
		      (conjugate-verb 'to-open ($ agent 'player?))))	      
	     ((bitvector-ref visibility (row-major 
					 (car new-location)
					 (cadr new-location) ($ level 'get-cols)))
	      ($ level 'remember (car new-location) (cadr new-location))
	      (format #f "The door ~a." (conjugate-verb 'to-open #f)))
	     (else #f))))
	 #t)
	(($ agent 'player?)
	 (let ((has-memory 
		($ level 'has-memory-of? (car new-location) (cadr new-location))))
	   ($ level 'remember (car new-location) (cadr new-location))
	   (not has-memory)) 
	 #f)
	(else #f)))

(define (move-agent-direction-long level agent direction)                                  
  (if (move-agent-direction level agent direction)
      (if (not ($ agent #:def #f 'interrupted?))
	  (begin (set! ($ agent 'saved-command) `(,direction long)) #t)
	  (begin (set! ($ agent 'saved-command) #f) #t))
      (begin (set! ($ agent 'saved-command) #f) #f)))

(define move-agent-direction 
  (lambda (level agent direction)
    (let* ((row ($ agent 'row))
	   (col ($ agent 'col))
	   (new-location (make-new-location (list row col) direction))) 
      (move-agent level agent new-location))))

(define-objects-public Agent  
  ((initialize! 
    (method ()
      (if (not ($ this 'body #:def #f)) 
	  (set! ($ this 'body) (instance 'UnknownBody #:args '())))
      (set! ($ this 'timers) '())
      (set! ($ this 'items) '()))) 
   (set-location! 
    (method (location) 
      (set! ($ this 'row) (car location))
      (set! ($ this 'col) (cadr location))))
   (location wrap-location)
   (interrupted? #f)
   (interrupt! (method () 
		 (set! ($ this 'interrupted?) #t)
		 (set! ($ this 'saved-command) #f)
		 (set! ($ this 'count) #f)))
   (clear-interrupt! (method ()
		       (set! ($ this 'interrupted?) #f)))
   (add-item! 
    (method (item) 
      (letrec* ((letters (map (lambda (item) ($ item #:def #\? 'letter)) ($ this 'items))))
	(let set-letter-and-insert ((test-letters (iota 52)))
	  (if (null? test-letters) 
	      (begin (if ($ this 'player? #:def #f) (message "No room for that!")) #f)
	      (let ((letter (integer->char (+ (car test-letters) 97))))
		(if (let find-letter ((letters letters) (test-letter letter))
		      (cond
		       ((null? letters) #t)
		       ((eq? (car letters) test-letter) #f)
		       (else (find-letter (cdr letters) test-letter))))
		    (begin (set! ($ item 'letter) letter)
			   (set! ($ this 'items) (append ($ this 'items) (list item)))
			   (set! ($ item 'location) 
				 (method () ($ ($ this 'container) 'location)))
			   (set! ($ item 'container) (object-reference this))
			   #t)
		    (set-letter-and-insert (cdr test-letters)))))))))
   (player? #f)
   (blind? (method () ($ ($ this 'body) 'blind?)))
   (can-open-doors? #f)
   (on-enter-square 
    (method (level location)
      (if ($ level 'weights #:def #f)
	  (set! ($ level `(weights (,($ this 'row) ,($ this 'col)))) 
		10000))))
   (on-leave-square 
    (method (level location)
      (if ($ level 'weights #:def #f)
	  (set! ($ level `(weights (,($ this 'row) ,($ this 'col)))) 
		($ level `(squares (,($ this 'row) ,($ this 'col)) weight))))))
   (move-to-empty-location 
    (method (level #:optional original-location (attempts 1))
      (if (= attempts 32) 
	  ($ this 'set-location! 
	     ($ level 'random-location
		(lambda (square loc) 
		  (and ($ square 'can-agent-enter?)
		       ($ level 'can-agent-enter-location? loc)))))
	  (let move-me ((dirs all-directions))
	    (let* ((new-dir (list-ref-random dirs))
		   (new-loc (make-new-location ($ this 'location) new-dir)))
	      (if (($ level ($ list 'squares new-loc)) 'can-agent-enter? this)
		  (let ((blocking-agent ($ level 'agent-at new-loc)))
		    (set! ($ this 'row) (car new-loc))
		    (set! ($ this 'col) (cadr new-loc))
		    (if (or blocking-agent (equal? new-loc original-location)) 
			($ this 'move-to-empty-location level 
			   (or original-location ($ this 'location)) (+ attempts 1))))
		  (if (> (length dirs) 1) (move-me (delete new-dir dirs)))))))))
   (describe 
    (method () 
      (format #f "~a ~a" (indefinite-article-for ($ this 'name)) ($ this 'name))))
   (describe-definite (method () (format #f "the ~a" ($ this 'name))))
   (describe-possessive (method () (format #f "the ~a's" ($ this 'name))))
   (rarity 'common)
   (level 1)
   (square-interact (method (level new-location) #t))
   (remove-item! wrap-remove-item)
   (can-melee? #t)
   (can-move? #t)
   (status 'playing)
   (choose-weapon
    (method ()
      (or (list-ref-random 
	   (filter (pred-and 
		    (applicator 'weapon? #:def #f) 
		    (applicator 'wielded? #:def #f)) 
		   ($ this 'items)))	    
	  (list-ref-random ($ ($ this 'body) 'melee-parts)))))
   (melee-attack 
    (method (target level)
      (let* ((weapon ($ this 'choose-weapon)))
	(if weapon
	 (let*
	     ((part ($ ($ target 'body) 'choose-by-weight))
	      (attack-success? #t)
	      (verb (list-ref-random ($ weapon 'melee-verbs))))
	   (or
	    (message-player 
	     level ($ this 'location)
	     (lambda (visibility)
	       (if (bitvector-ref
		    visibility 
		    (row-major (car ($ target 'location)) 
			       (cadr ($ target 'location)) 
			       (cadr (array-dimensions ($ level 'squares)))))
		   (sentence-agent-verb-agent-possessive 
		    this verb target ($ part 'describe))
		   (sentence-agent-verb-agent this verb "it"))))
	    (message-player 
	     level ($ target 'location) 
	     (sentence-possessive-item-verb-passive target ($ part 'describe) 'to-attack)))
	   (if attack-success? ($ part 'damage level target 
				  ($ weapon 'slicing) 
				  ($ weapon 'heft) 
				  ($ weapon 'sharpness)))
	   #t)
	 #f))))
   (speed 1000)		     
   (erratic-movement 0)
   (take-turn 
    (method (paths-to-player player level) 
      (or 
       (if ($ this 'can-move?) 
	   (move-agent level this 
		       (array-ref paths-to-player ($ this 'row) ($ this 'col))) #f)
       (if (and ($ this 'can-melee?) 
		(locations-adjacent? ($ player 'location) ($ this 'location)))
	   ($ this 'melee-attack player level)))
      #t)))
  ((Humanoid  
    ((initialize! 
       (method ()
	 (set! ($ this 'body) (instance HumanoidBody #:args '()))
	 ((super this) 'initialize!)))
      (symbol 'human)
      (name "humanoid")
      (can-open-doors? #t)
      (speed 1000))
    ((Siren
      ((name "siren")
       (describe-long "An unbelievably gorgeous lady with fins in place of legs.\
 She doesn't move much, but you find yourself inexorably drawn to the\
 sound of her voice.")
       (rarity 'rare)
       (level 10)
       (can-move? #f)
       (ranged-attack 
	(method (agent) 
	  (message (format #f "The siren pulls ~a in with her song" 
			   ($ agent 'describe-definite)))))))
     (Orc 
      ((symbol 'orc)
       (name "orc")
       (can-open-doors? #t)
       (speed 2000))
      ((Orcling
	((name "orcling")
	 (describe-long "A little orc, barely waist-high, shuffling about aimlessly. \
It almost seems cute... until it bares its enormous, fully-grown fangs at you!")
	 (erratic-movement 1)
	 (level 1)))))))
   (Mollusc
    ((symbol 'mollusc)
     (name "mollusc")
     (speed 3000))
    ((GiantSlug
      ((initialize! (method ()
		      (set! ($ this 'body) (instance SlugBody #:args '()))
		      ((super this) 'initialize!))) 
       (name "giant slug")
       (describe-long "A disgusting, six-foot long mass of mucous-covered flesh. \
It's bulbous eye-stalks are full of murderous intent.")
       (level 2)))))))
   ;; (Arthropod
   ;;  ((initialize! (method (segment-count)
   ;; 		    (set! (this 'body) (instance ArthropodBody #:args '(segment-count)))
   ;; 		    (super 'initialize!)))
   ;;   (symbol 'arthropod)
   ;;   (speed 1000)
   ;;   (name "arthropod"))
   ;;  ((Scorpion
   ;;    ((initialize! (method ()
   ;; 		      (super 'initialize! 4)
   ;; 		      ((this 'body) 'add-part (instance Stinger) 'abdomen)))
   ;;     (level 2)
   ;;     (name "scorpion")))))))
