(* This file is free software, part of linol. See file "LICENSE" for more information *)

(* Some user code

   The code here is just a placeholder to make this file compile, it is expected
   that users have an implementation of a processing function for input contents.

   Here we expect a few things:
   - a type to represent a state/environment that results from processing an
     input file
   - a function procdessing an input file (given the file contents as a string),
     which return a state/environment
   - a function to extract a list of diagnostics from a state/environment.
     Diagnostics includes all the warnings, errors and messages that the processing
     of a document are expected to be able to return.
*)

type state_after_processing = unit

let process_some_input_file (_file_contents : string) : state_after_processing =
  ()

let diagnostics (_state : state_after_processing) : Lsp.Types.Diagnostic.t list =
  []


(* Lsp server class

   This is the main point of interaction beetween the code checking documents
   (parsing, typing, etc...), and the code of linol.

   The [Linol_lwt.Jsonrpc2.server] class defines a method for each of the action
   that the lsp server receives, such as opening of a document, when a document
   changes, etc.. By default, the method predefined does nothing (or errors out ?),
   so that users only need to override methods that they want the server to
   actually meaningfully interpret and respond to.
*)
class lsp_server =
  object(self)
    inherit Linol_lwt.Jsonrpc2.server

    (* one env per document *)
    val buffers: (Lsp.Types.DocumentUri.t, state_after_processing) Hashtbl.t
      = Hashtbl.create 32

    (* We define here a helper method that will:
       - process a document
       - store the state resulting from the processing
       - return the diagnostics from the new state
    *)
    method private _on_doc
        ~(notify_back:Linol_lwt.Jsonrpc2.notify_back)
        (uri:Lsp.Types.DocumentUri.t) (contents:string) =
      let new_state = process_some_input_file contents in
      Hashtbl.replace buffers uri new_state;
      let diags = diagnostics new_state in
      notify_back#send_diagnostic diags

    (* We now override the [on_notify_doc_did_open] method that will be called
       by the server each time a new document is opened. *)
    method on_notif_doc_did_open ~notify_back d ~content : unit Linol_lwt.Task.m =
      self#_on_doc ~notify_back d.uri content

    (* Similarly, we also override the [on_notify_doc_did_change] method that will be called
       by the server each time a new document is opened. *)
    method on_notif_doc_did_change ~notify_back d _c ~old_content:_old ~new_content =
      self#_on_doc ~notify_back d.uri new_content

    (* On document closes, we remove the state associated to the file from the global
       hashtable state, to avoid leaking memory. *)
    method on_notif_doc_did_close ~notify_back:_ d : unit Linol_lwt.Task.m =
      Hashtbl.remove buffers d.uri;
      Linol_lwt.Jsonrpc2.IO.return ()

  end

(* Main code
   This is the code that creates an instance of the lsp server class
   and runs it as a task. *)
let run () =
  let open Linol_lwt.Task.Infix in
  let s = new lsp_server in
  (* TODO: the task is the LSP server *)
  let task =
    Linol_lwt.Task.start ~descr:"top task"
      (fun _top_task ->
         let server = Linol_lwt.Jsonrpc2.create_stdio s in
         let* () =
           Linol_lwt.Task.run_sub ~descr:"lsp server" ~parent:_top_task
             (fun _ -> Linol_lwt.Jsonrpc2.run server _top_task)
           >>= Linol_lwt.Task.unwrap
         in
         Linol_lwt.Task.return ()
      )
  in
  match Linol_lwt.Task.run task with
  | Ok () -> ()
  | Error e ->
    let e = Printexc.to_string e in
    Printf.eprintf "error: %s\n%!" e;
    exit 1

(* Finally, we actually run the server *)
let () = run ()

