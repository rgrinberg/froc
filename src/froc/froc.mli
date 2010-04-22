(*
 * This file is part of froc, a library for functional reactive programming
 * Copyright (C) 2009-2010 Jacob Donham
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public
 * License as published by the Free Software Foundation; either
 * version 2 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Library General Public License for more details.
 *
 * You should have received a copy of the GNU Library General Public
 * License along with this library; if not, write to the Free
 * Software Foundation, Inc., 59 Temple Place - Suite 330, Boston,
 * MA 02111-1307, USA
 *)

(** Functional reactive programming *)
(**
   {2 Overview}

   [Froc] implements functional reactive programming in the style of
   FrTime / Flapjax (but typed). It uses the dynamic dependency graph
   of Acar et al. (self-adjusting computation). Behaviors are
   presented as monadic values, using ideas from [Lwt].

   A {e behavior} is a monadic value that can change over
   time. Binding a behavior causes the binder to be made a dependency
   of the behavior, and to be re-executed when the behavior changes.

   An {e event} is a channel over which values may be sent (using the
   associated {e event_sender}). Listeners on the channel are notified
   when an event occurs (i.e. a value is sent on the channel).

   Sent events are queued; after each event in the queue is sent and
   its listeners notified, the dependency graph is processed to update
   any affected behaviors in a consistent way.

   When a dependency of a behavior must be re-executed, all resources
   (i.e. binds and notifies) used in the previous execution are
   released, and all cleanup functions set in the previous execution
   are run (see [cleanup]).
*)

val init : unit -> unit
  (** Initialize the library. Must be called before any other function. *)

type cancel
  (** Type of handles to listener registrations. *)

val no_cancel : cancel
  (** Dummy cancel. *)

val cancel : cancel -> unit
  (** Cancels a listener registration using the given handle. *)

(** {2 Behaviors} *)

type 'a behavior
  (** Type of behaviors of type ['a]. *)

(** Type of values of type ['a] or exception. *)
type 'a result = Value of 'a | Fail of exn

val return : 'a -> 'a behavior
  (**
     [return v] is a constant behavior with value [v].
  *)

val fail : exn -> 'a behavior
  (**
     [fail e] is a constant behavior that fails with the exception [e].
  *)

val bind : ?eq:('b -> 'b -> bool) -> 'a behavior -> ('a -> 'b behavior) -> 'b behavior
  (**
     [bind b f] behaves as [f] applied to the value of [b]. If [b]
     fails, [bind b f] also fails, with the same exception.

     When the value of a behavior changes, all functions [f] bound to
     it are re-executed.
  *)

val (>>=) : 'a behavior -> ('a -> 'b behavior) -> 'b behavior
  (**
     [b >>= f] is an alternative notation for [bind b f].
  *)

val blift : ?eq:('b -> 'b -> bool) -> 'a behavior -> ('a -> 'b) -> 'b behavior
  (**
     [blift b ?eq f] is equivalent to [bind b (fun v -> return ?eq (f
     v))], but is slightly more efficient.
  *)

val lift : ?eq:('b -> 'b -> bool) -> ('a -> 'b) -> 'a behavior -> 'b behavior
  (**
     [lift ?eq f b] is equivalent to [blift b ?eq f]; it can be
     partially applied to lift a function to the monad without yet
     binding it to a behavior.
  *)

val catch : ?eq:('a -> 'a -> bool) -> (unit -> 'a behavior) -> (exn -> 'a behavior) -> 'a behavior
  (**
     [catch b f] behaves the same as [b()] if [b()] succeeds. If [b()]
     fails with some exception [e], [catch b f] behaves as [f e].
  *)

val catch_lift : ?eq:('a -> 'a -> bool) -> (unit -> 'a behavior) -> (exn -> 'a) -> 'a behavior
  (**
     [catch_lift b ?eq f] is equivalent to [catch b (fun e -> return
     ?eq (f e))], but is slightly more efficient.
  *)

val try_bind : ?eq:('b -> 'b -> bool) -> (unit -> 'a behavior) -> ('a -> 'b behavior) -> (exn -> 'b behavior) -> 'b behavior
  (**
     [try_bind b f g] behaves as [bind (b()) f] if [b()] succeeds. If
     [b()] fails with exception [e], [try_bind b f g] behaves as [g
     e].
  *)

val try_bind_lift : ?eq:('b -> 'b -> bool) -> (unit -> 'a behavior) -> ('a -> 'b) -> (exn -> 'b) -> 'b behavior
  (**
     [try_bind_lift b ?eq f g] is equivalent to [try_bind b (fun v ->
     return ?eq (f v)) (fun e -> return ?eq (g e))], but is slightly
     more efficient.
  *)

val read : 'a behavior -> 'a
  (**

     [read b] returns the current value of [b]; if [b] fails with
     exception [e] it raises [e].

     Since [read] doesn't go through the dependency tracking
     machinery, it can get a stale value if called at the wrong
     time. You probably want [bind] instead.
  *)

val read_result : 'a behavior -> 'a result
  (**
     Same as [read] but returns a result instead of possibly raising
     an exception.
  *)

val notify_b : 'a behavior -> ('a -> unit) -> unit
  (**
     Adds a listener for the value of a behavior, which is called
     whenever the value changes. When the behavior fails the listener
     is not called. The notification is implicitly cancelled when the
     calling context is re-run.
  *)

val notify_b_cancel : 'a behavior -> ('a -> unit) -> cancel
  (**
     Same as [notify_b], but not implicitly cancelled; an explicit
     cancel handle is returned.
  *)

val notify_result_b : 'a behavior -> ('a result -> unit) -> unit
  (**
     Same as [notify_b] but the listener is called with a result when
     the value changes or when the behavior fails.
  *)

val notify_result_b_cancel : 'a behavior -> ('a result -> unit) -> cancel
  (**
     Same as [notify_b_cancel] but the listener is called with a
     result when the value changes or when the behavior fails.
  *)

val cleanup : (unit -> unit) -> unit
  (**
     When called in the context of a binder, adds a function to be
     called when the binder must be re-executed. You can use this to
     clean up external resources.

     Binds and notifies in the context of a binder are cleaned up
     automatically.
  *)

val memo :
  ?size:int -> ?hash:('a -> int) -> ?eq:('a -> 'a -> bool) -> unit ->
  ('a -> 'b) ->
  ('a -> 'b)
  (**
     [memo f] creates a {e memo function} from [f]. Calls to the memo
     function are memoized and may be reused when the calling context
     is re-executed.

     [memo] does not provide general-purpose memoization; calls may be
     reused only within the calling context in which they originally
     occurred, and only in the original order they occurred.

     To memoize a recursive function, use the following idiom: {[
       let m = memo () in
       let rec f x = ... memo f y in
       let f x = memo f x
     ]}

     The default hash function is not appropriate for behaviors and
     events (since they contain mutable data) so you should use
     [hash_behavior] and [hash_event] instead.
  *)

val hash_behavior : 'a behavior -> int
  (** A hash function for behaviors, *)


(** {2 Events} *)

type +'a event
  (** Type of events of type ['a]. *)

type -'a event_sender
  (** Type of event senders of type ['a]. *)

val make_event : unit -> 'a event * 'a event_sender
  (** Makes a new channel for events of type ['a]. *)

val never : 'a event
  (** An event which never occurs. *)

val notify_e : 'a event -> ('a -> unit) -> unit
  (**
     Adds a listener on the channel, which is called whenever a value
     is sent on it. When a failure is sent the listener is not
     called. The notification is implicitly cancelled when the calling
     context is re-run.
  *)

val notify_e_cancel : 'a event -> ('a -> unit) -> cancel
  (**
     Same as [notify_e], but not implicitly cancelled; an explicit
     cancel handle is returned.
  *)

val notify_result_e : 'a event -> ('a result -> unit) -> unit
  (**
     Same as [notify_e] but the listener is called with a result when
     a value or a failure is sent.
  *)

val notify_result_e_cancel : 'a event -> ('a result -> unit) -> cancel
  (**
     Same as [notify_e_cancel] but the listener is called with a result when
     a value or a failure is sent.
  *)

val send : 'a event_sender -> 'a -> unit
  (** [send e v] calls the listeners of the associated event with [Value v]. *) 

val send_exn : 'a event_sender -> exn -> unit
  (** [send_exn e x] calls the listeners of the associated event with [Fail x]. *) 

val send_result : 'a event_sender -> 'a result -> unit
  (** [send_result e r] calls the listeners of the associated event with [r]. *)

val next : 'a event -> 'a event
  (** [next e] fires just the next occurence of [e]. *)

val merge : 'a event list -> 'a event
  (** [merge es] is an event that fires whenever any of the events in [e] fire. *)

val map : ('a -> 'b) -> 'a event -> 'b event
  (** [map f e] is an event that fires [f v] whenever [e] fires [v]. *)

val filter : ('a -> bool) -> 'a event -> 'a event
  (** [filter p e] is an event that fires [v] whenever [e] fires [v] and [p v] is true. *)

val collect : ('b -> 'a -> 'b) -> 'b -> 'a event -> 'b event
  (**
     [collect f b e] is an event that maintains an internal state [s]
     (initialized to [b]); whenever [e] fires [v], [s'] becomes [f s
     v], the event fires [s'], and [s'] becomes the new internal
     state.
  *)

val hash_event : 'a event -> int
  (** A hash function for events. *)

(** {2 Derived operations} *)

val switch_bb : ?eq:('a -> 'a -> bool) -> 'a behavior behavior -> 'a behavior
  (** [switch_bb b] behaves as whichever behavior is currently the value of [b]. *)

val switch_be : ?eq:('a -> 'a -> bool) -> 'a behavior -> 'a behavior event -> 'a behavior
  (** [switch_be b e] behaves as [b] until [e] fires, then behaves as the last value of [e]. *)

val until : ?eq:('a -> 'a -> bool) -> 'a behavior -> 'a behavior event -> 'a behavior
  (** [until b e] behaves as [b] until [e] fires [b'], then behaves as [b'] *)

val hold : ?eq:('a -> 'a -> bool) -> 'a -> 'a event -> 'a behavior
  (**
     [hold v e] behaves as the last value fired by [e], or [v] if [e]
     has not yet fired a value (since [hold] was called). [eq]
     gives the equality on the resulting behavior.
  *)

val hold_result : ?eq:('a -> 'a -> bool) -> 'a result -> 'a event -> 'a behavior
  (**
     [hold_result] is the same as [hold] but initialized with a result
     instead of a value.
  *)

val changes : 'a behavior -> 'a event
  (** [changes b] fires the value of [b] whenever it changes. *)


val when_true : bool behavior -> unit event
  (** [when_true b] fires whenever [b] becomes true. *)

val count : 'a event -> int behavior
  (**
     [count e] behaves as the number of times [e] has fired (since
     [count] was called).
  *)

val make_cell : 'a -> 'a behavior * ('a -> unit)
  (**
     [make_cell v] returns a behavior (with initial value [v]) and a
     setter function which changes the behavior's value. The setter
     respects the update cycle (it enqueues an event) so may be used
     freely.
  *)

(** {2 Variations} *)

val bindN : ?eq:('b -> 'b -> bool) -> 'a behavior list -> ('a list -> 'b behavior) -> 'b behavior
val bliftN : ?eq:('b -> 'b -> bool) -> 'a behavior list -> ('a list -> 'b) -> 'b behavior
val liftN : ?eq:('b -> 'b -> bool) -> ('a list -> 'b) -> 'a behavior list -> 'b behavior

val bind2 :
  ?eq:('b -> 'b -> bool) ->
  'a1 behavior -> 'a2 behavior ->
  ('a1 -> 'a2 -> 'b behavior) ->
  'b behavior
val blift2 :
  ?eq:('b -> 'b -> bool) ->
  'a1 behavior -> 'a2 behavior ->
  ('a1 -> 'a2 -> 'b) ->
  'b behavior
val lift2 :
  ?eq:('b -> 'b -> bool) ->
  ('a1 -> 'a2 -> 'b) ->
  'a1 behavior -> 'a2 behavior ->
  'b behavior

val bind3 :
  ?eq:('b -> 'b -> bool) ->
  'a1 behavior -> 'a2 behavior -> 'a3 behavior ->
  ('a1 -> 'a2 -> 'a3 -> 'b behavior) ->
  'b behavior
val blift3 :
  ?eq:('b -> 'b -> bool) ->
  'a1 behavior -> 'a2 behavior -> 'a3 behavior ->
  ('a1 -> 'a2 -> 'a3 -> 'b) ->
  'b behavior
val lift3 :
  ?eq:('b -> 'b -> bool) ->
  ('a1 -> 'a2 -> 'a3 -> 'b) ->
  'a1 behavior -> 'a2 behavior -> 'a3 behavior ->
  'b behavior

val bind4 :
  ?eq:('b -> 'b -> bool) ->
  'a1 behavior -> 'a2 behavior -> 'a3 behavior -> 'a4 behavior ->
  ('a1 -> 'a2 -> 'a3 -> 'a4 -> 'b behavior) ->
  'b behavior
val blift4 :
  ?eq:('b -> 'b -> bool) ->
  'a1 behavior -> 'a2 behavior -> 'a3 behavior -> 'a4 behavior ->
  ('a1 -> 'a2 -> 'a3 -> 'a4 -> 'b) ->
  'b behavior
val lift4 :
  ?eq:('b -> 'b -> bool) ->
  ('a1 -> 'a2 -> 'a3 -> 'a4 -> 'b) ->
  'a1 behavior -> 'a2 behavior -> 'a3 behavior -> 'a4 behavior ->
  'b behavior

val bind5 :
  ?eq:('b -> 'b -> bool) ->
  'a1 behavior -> 'a2 behavior -> 'a3 behavior -> 'a4 behavior -> 'a5 behavior ->
  ('a1 -> 'a2 -> 'a3 -> 'a4 -> 'a5 -> 'b behavior) ->
  'b behavior
val blift5 :
  ?eq:('b -> 'b -> bool) ->
  'a1 behavior -> 'a2 behavior -> 'a3 behavior -> 'a4 behavior -> 'a5 behavior ->
  ('a1 -> 'a2 -> 'a3 -> 'a4 -> 'a5 -> 'b) ->
  'b behavior
val lift5 :
  ?eq:('b -> 'b -> bool) ->
  ('a1 -> 'a2 -> 'a3 -> 'a4 -> 'a5 -> 'b) ->
  'a1 behavior -> 'a2 behavior -> 'a3 behavior -> 'a4 behavior -> 'a5 behavior ->
  'b behavior

val bind6 :
  ?eq:('b -> 'b -> bool) ->
  'a1 behavior -> 'a2 behavior -> 'a3 behavior -> 'a4 behavior -> 'a5 behavior -> 'a6 behavior ->
  ('a1 -> 'a2 -> 'a3 -> 'a4 -> 'a5 -> 'a6 -> 'b behavior) ->
  'b behavior
val blift6 :
  ?eq:('b -> 'b -> bool) ->
  'a1 behavior -> 'a2 behavior -> 'a3 behavior -> 'a4 behavior -> 'a5 behavior -> 'a6 behavior ->
  ('a1 -> 'a2 -> 'a3 -> 'a4 -> 'a5 -> 'a6 -> 'b) ->
  'b behavior
val lift6 :
  ?eq:('b -> 'b -> bool) ->
  ('a1 -> 'a2 -> 'a3 -> 'a4 -> 'a5 -> 'a6 -> 'b) ->
  'a1 behavior -> 'a2 behavior -> 'a3 behavior -> 'a4 behavior -> 'a5 behavior -> 'a6 behavior ->
  'b behavior

val bind7 :
  ?eq:('b -> 'b -> bool) ->
  'a1 behavior -> 'a2 behavior -> 'a3 behavior -> 'a4 behavior -> 'a5 behavior -> 'a6 behavior -> 'a7 behavior ->
  ('a1 -> 'a2 -> 'a3 -> 'a4 -> 'a5 -> 'a6 -> 'a7 -> 'b behavior) ->
  'b behavior
val blift7 :
  ?eq:('b -> 'b -> bool) ->
  'a1 behavior -> 'a2 behavior -> 'a3 behavior -> 'a4 behavior -> 'a5 behavior -> 'a6 behavior -> 'a7 behavior ->
  ('a1 -> 'a2 -> 'a3 -> 'a4 -> 'a5 -> 'a6 -> 'a7 -> 'b) ->
  'b behavior
val lift7 :
  ?eq:('b -> 'b -> bool) ->
  ('a1 -> 'a2 -> 'a3 -> 'a4 -> 'a5 -> 'a6 -> 'a7 -> 'b) ->
  'a1 behavior -> 'a2 behavior -> 'a3 behavior -> 'a4 behavior -> 'a5 behavior -> 'a6 behavior -> 'a7 behavior ->
  'b behavior

(** {2 Debugging} *)

val set_exn_handler : (exn -> unit) -> unit
  (**
     Set an exception handler which is called on exceptions from
     notification functions.
  *)

val set_debug : (string -> unit) -> unit
  (** Set a function for showing library debugging. *)
