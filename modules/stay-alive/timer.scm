;; Updated!
(define-module (stay-alive timer)
  #:use-module (shelf shelf)
  #:use-module (stay-alive ncurses-interface)
  #:export (Timer LightSourceTimer))

(define-objects Timer
  ((initialize! (method (time tick #:optional gate)
		  (set! ($ this 'time) time)
		  (set! ($ this 'tick-internal) tick)))
   (tick (method (#:optional level)
	   (if ($ this 'gate #:def #t)
	       (begin (set! ($ this 'time) (- ($ this 'time) 1))
		      ($ this 'tick-internal level)))
	   (> ($ this 'time) 0))))
  ((LightSourceTimer
    ((initialize! (method (torch time)
		    (set! ($ this 'torch) (object-reference torch))
		    (set! ($ this 'time) time)))
     (gate (method ()
	     ($ this '(torch lit?) #:def #f)))
     (tick-internal 
      (method (level) 
	(if (= ($ this 'time) 0)
	    (begin
	      (set! ($ ($ this 'torch) 'lightable?) #f)
	      (set! ($ ($ this 'torch) 'lit?) #f)
	      (message-player 
	       level 
	       ($ ($ this 'torch) 'location) "The torch burns out")))))))))
