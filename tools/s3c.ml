(** command-line client to Amazon's S3 *)

open Lwt
open Creds
open Printf

module C = CalendarLib.Calendar
module P = CalendarLib.Printer.CalendarPrinter

module Util = Aws_util

let redirect = function
  | Some region ->
      print_endline ("premament redirect to region " ^ (S3.string_of_region region))
  | None ->
    print_endline "premament redirect to unknown region"

let create_bucket creds region bucket () =
  lwt result = S3.create_bucket creds region bucket `Private in
  let exit_code =
    match result with
      | `Ok -> print_endline "ok"; 0
      | `Error msg -> print_endline msg; 1
  in
  return exit_code

let delete_bucket creds region bucket () =
  lwt result = S3.delete_bucket creds region bucket in
  let exit_code =
    match result with
    | `Ok -> print_endline "ok"; 0
    | `Error msg -> print_endline msg; 1
    | `PermanentRedirect region -> redirect region; 1
  in
  return exit_code

let list_buckets creds region () =
  lwt result = S3.list_buckets creds region in
  let exit_code =
    match result with
      | `Ok bucket_infos ->
        List.iter (
          fun b ->
            printf "%s\t%s\n" b#creation_date b#name
        ) bucket_infos;
        0
      | `Error body -> print_endline body; 1
      | `PermanentRedirect region -> redirect region; 1
  in
  return exit_code

let get_object_s creds region bucket objekt () =
  lwt result = S3.get_object_s (Some creds) region ~bucket ~objekt in
  let exit_code =
    match result with
      | `Ok body -> print_string body; 0
      | `AccessDenied -> print_endline "access denied"; 0
      | `NotFound -> printf "%s/%s not found\n%!" bucket objekt; 0
      | `Error msg -> print_endline msg; 1
      | `PermanentRedirect region -> redirect region; 1
  in
  return exit_code

let get_object creds region bucket objekt path () =
  lwt result = S3.get_object (Some creds) region ~bucket ~objekt ~path in
  let exit_code =
    match result with
      | `Ok -> print_endline "ok"; 0
      | `AccessDenied -> print_endline "access denied"; 0
      | `NotFound -> printf "%s/%s not found\n%!" bucket objekt; 0
      | `Error msg -> print_endline msg; 1
      | `PermanentRedirect region -> redirect region; 1
  in
  return exit_code

let get_object_range creds region bucket objekt path start fini () =
  lwt result = S3.get_object ~byte_range:(start, fini) (Some creds) region
    ~bucket ~objekt ~path in
  let exit_code =
    match result with
      | `Ok -> print_endline "ok"; 0
      | `AccessDenied -> print_endline "access denied"; 0
      | `NotFound -> printf "%s/%s not found\n%!" bucket objekt; 0
      | `Error msg -> print_endline msg; 1
      | `PermanentRedirect region -> redirect region; 1
  in
  return exit_code

let put_object creds region bucket objekt path () =
  lwt result = S3.put_object creds region ~bucket ~objekt ~body:(`File path) in
  let exit_code =
    match result with
      | `Ok -> 0
      | `AccessDenied -> print_endline "access denied"; 0
      | `Error msg -> print_endline msg; 1
      | `PermanentRedirect region -> redirect region; 1
  in
  return exit_code

let put_object_s creds region bucket objekt contents () =
  lwt result = S3.put_object creds region ~bucket ~objekt ~body:(`String contents) in
  let exit_code =
    match result with
      | `Ok -> 0
      | `AccessDenied -> print_endline "access denied"; 0
      | `Error msg -> print_endline msg; 1
      | `PermanentRedirect region -> redirect region; 1
  in
  return exit_code

let delete_object creds region bucket objekt () =
  lwt result = S3.delete_object creds region ~bucket ~objekt in
  let exit_code =
    match result with
      | `Ok -> 0
      | `BucketNotFound -> printf "%s not found\n%!" bucket; 0
      | `Error msg -> print_endline msg; 1
      | `PermanentRedirect region -> redirect region; 1
  in
  return exit_code


let print_kv_list kv_list =
  List.iter (
    fun (k,v) ->
      printf "%s: %s\n" k v
  ) kv_list

let get_object_metadata creds region bucket objekt () =
  lwt result = S3.get_object_metadata creds region ~bucket ~objekt in
  let exit_code =
    match result with
      | `Ok m ->
        print_kv_list [
          "Content-Type", m#content_type;
          "Content-Length", string_of_int m#content_length;
          "ETag", m#etag;
          "Last-Modified", Util.date_string_of_unixfloat m#last_modified
        ];
        0
      | `NotFound -> printf "%s/%s not found\n%!" bucket objekt; 1
      | `Error msg -> print_endline msg; 1
      | `PermanentRedirect region -> redirect region; 1
  in
  return exit_code

let some_or_empty = function
  | Some s -> s
  | None -> ""

let list_objects creds region bucket () =
  lwt result = S3.list_objects creds region bucket in
  let exit_code =
    match result with
      | `Ok res ->
        print_kv_list [
          "name", res#name;
          "prefix", (some_or_empty res#prefix);
          "marker", (some_or_empty res#marker);
          "truncated", (string_of_bool res#is_truncated);
          "objects", ""
        ];
        List.iter (
          fun o ->
            printf "%s\t%s\t%s\t%d\t%s\t%s\t%s\n"
              o#name
              (Util.date_string_of_unixfloat o#last_modified)
              o#etag
              o#size
              o#storage_class
              (match o#owner with Some owner -> owner#id | None -> "--")
              (match o#owner with Some owner -> owner#display_name | None -> "--")
        ) res#objects;
        0
      | `NotFound -> printf "bucket %s not found\n%!" bucket; 1
      | `Error msg -> print_endline msg; 1
      | `PermanentRedirect region -> redirect region; 1
  in
  return exit_code

let print_acl acl =
  printf "owner: %s\n" (S3.string_of_identity acl#owner);
  print_endline "grants:";
  List.iter (
    fun (grantee, permission) ->
      printf "%s: %s\n" (S3.string_of_identity grantee)
        (S3.string_of_permission permission);
  ) acl#grants

let get_bucket_acl creds region bucket () =
  lwt result = S3.get_bucket_acl creds region bucket in
  let exit_code =
    match result with
      | `Ok acl -> print_acl acl; 0
      | `NotFound -> printf "bucket %s not found\n%!" bucket; 1
      | `Error msg -> print_endline msg; 1
      | `PermanentRedirect region -> redirect region; 1
  in
  return exit_code

let grant_bucket_permission creds region bucket
    ~grantee_aws_id
    ~grantee_aws_display_name
    ~permission
    () =
  (* create identities from id and display_name *)
  let grantee =
    let cn = new S3.canonical_user ~id:grantee_aws_id
      ~display_name:grantee_aws_display_name in
    `canonical_user cn
  in

  (* get the acl *)
  lwt result = S3.get_bucket_acl creds region bucket in
  lwt exit_code =
    match result with
      | `Ok acl -> (

        (* now that we have the acl, modified it by adding to it yet another grant *)
        let grant = grantee, S3.permission_of_string permission in
        let acl_1 = new S3.acl acl#owner (grant :: acl#grants) in
        lwt result = S3.set_bucket_acl creds region bucket acl_1 in
        let exit_code =
          match result with
            | `Ok -> print_endline "ok"; 0
            | `NotFound -> printf "setting bucket acl on %s failed\n%!" bucket; 1
            | `Error msg -> print_endline msg; 1
            | `PermanentRedirect region -> redirect region; 1
        in
        return exit_code
      )

      | `NotFound -> printf "getting bucket acl on %s failed\n%!" bucket; return 1
      | `Error msg -> print_endline msg; return 1
      | `PermanentRedirect region -> redirect region; return 1
  in
  return exit_code

(* ignore display name *)
let grants_not_equal (grantee_1,perm_1) (grantee_2,perm_2) =
  if perm_1 <> perm_2 then
    true
  else
    match grantee_1, grantee_2 with
      | `canonical_user cn1, `canonical_user cn2 -> cn1#id <> cn2#id
      | _ -> true

let revoke_bucket_permission creds region bucket
    ~grantee_aws_id
    ~grantee_aws_display_name
    ~permission
    () =
  (* create identities from id and display_name *)
  let grantee =
    let cn = new S3.canonical_user ~id:grantee_aws_id
      ~display_name:grantee_aws_display_name in
    `canonical_user cn
  in

  (* construct the grant we wish to remove *)
  let permission = S3.permission_of_string permission in
  let grant = grantee, permission in

  (* get the acl *)
  lwt result = S3.get_bucket_acl creds region bucket in

  lwt exit_code =
    match result with
      | `Ok acl -> (

        (* find the grant needing to be removed *)
        let grants_1 = List.filter (fun g -> grants_not_equal g grant) acl#grants in
        if List.length grants_1 = List.length acl#grants then (
          print_endline "grant to be removed not found";
          return 1
        )
        else (
          (* construct a new acl without that grant *)
          let acl_1 = new S3.acl acl#owner grants_1 in
          lwt result = S3.set_bucket_acl creds region bucket acl_1 in
          let exit_code =
            match result with
                | `Ok -> print_endline "ok"; 0
                | `NotFound -> printf "setting bucket acl on %s failed\n%!" bucket; 1
                | `Error msg -> print_endline msg; 1
                | `PermanentRedirect region -> redirect region; 1
          in
          return exit_code
        )
      )

      | `NotFound -> printf "getting bucket acl on %s failed\n%!" bucket; return 1
      | `Error msg -> print_endline msg; return 1
      | `PermanentRedirect region -> redirect region; return 1
  in
  return exit_code

let get_object_acl creds region bucket objekt () =
  lwt result = S3.get_object_acl creds region ~bucket ~objekt in
  let exit_code =
    match result with
      | `Ok acl -> print_acl acl; 0
      | `NotFound -> printf "object %s/%s not found\n%!" bucket objekt; 1
      | `Error msg -> print_endline msg; 1
      | `PermanentRedirect region -> redirect region; 1
  in
  return exit_code

let grant_object_permission creds region ~bucket ~objekt
    ~grantee_aws_id
    ~grantee_aws_display_name
    ~permission
    () =
  (* create identities from id and display_name *)
  let grantee =
    let cn = new S3.canonical_user ~id:grantee_aws_id
      ~display_name:grantee_aws_display_name in
    `canonical_user cn
  in

  (* get the acl *)
  lwt result = S3.get_object_acl creds region bucket objekt in
  lwt exit_code =
    match result with
      | `Ok acl -> (

        (* now that we have the acl, modified it by adding to it yet
           another grant *)
        let grant = grantee, S3.permission_of_string permission in
        let acl_1 = new S3.acl acl#owner (grant :: acl#grants) in
        lwt result = S3.set_object_acl creds region ~bucket ~objekt acl_1 in
        let exit_code =
          match result with
            | `Ok -> print_endline "ok"; 0
            | `NotFound -> printf "setting bucket acl on %s failed\n%!" bucket; 1
            | `Error msg -> print_endline msg; 1
            | `PermanentRedirect region -> redirect region; 1
        in
        return exit_code
      )

      | `NotFound -> printf "getting object acl on %s/%s failed\n%!" bucket objekt;
        return 1

      | `Error msg -> print_endline msg; return 1
      | `PermanentRedirect region -> redirect region; return 1
  in
  return exit_code

let revoke_object_permission creds region ~bucket ~objekt
    ~grantee_aws_id
    ~grantee_aws_display_name
    ~permission
    () =
  (* create identities from id and display_name *)
  let grantee =
    let cn = new S3.canonical_user ~id:grantee_aws_id
      ~display_name:grantee_aws_display_name in
    `canonical_user cn
  in

  (* construct the grant we wish to remove *)
  let permission = S3.permission_of_string permission in
  let grant = grantee, permission in

  (* get the acl *)
  lwt result = S3.get_object_acl creds region ~bucket ~objekt in

  lwt exit_code =
    match result with
      | `Ok acl -> (

        (* find the grant needing to be removed *)
        let grants_1 = List.filter (fun g -> grants_not_equal g grant) acl#grants in
        if List.length grants_1 = List.length acl#grants then (
          print_endline "grant to be removed not found";
          return 1
        )
        else (
          (* construct a new acl without that grant *)
          let acl_1 = new S3.acl acl#owner grants_1 in
          lwt result = S3.set_object_acl creds region ~bucket ~objekt acl_1 in
          let exit_code =
            match result with
                | `Ok -> print_endline "ok"; 0
                | `NotFound ->
                  printf "setting object acl on %s/%s failed\n%!" bucket objekt; 1
                | `Error msg -> print_endline msg; 1
                | `PermanentRedirect region -> redirect region; 1
          in
          return exit_code
        )
      )

      | `NotFound -> printf "getting object acl on %s/%s failed\n%!" bucket objekt;
        return 1

      | `Error msg -> print_endline msg; return 1
      | `PermanentRedirect region -> redirect region; return 1
  in
  return exit_code

let get_bucket_policy creds region ~bucket () =
  S3.get_bucket_policy creds region ~bucket >>= function
    | `Ok policy -> print_endline policy; return 0
    | `AccessDenied -> print_endline "access denied"; return 1
    | `NotFound -> print_endline "not found"; return 1
    | `NotOwner -> print_endline "not owner"; return 1
    | `Error msg -> print_endline msg; return 1

let delete_bucket_policy creds region ~bucket () =
  S3.delete_bucket_policy creds region ~bucket >>= function
    | `Ok -> print_endline "ok"; return 0
    | `AccessDenied -> print_endline "access denied"; return 1
    | `NotOwner -> print_endline "not owner"; return 1
    | `Error msg -> print_endline msg; return 1


let set_bucket_policy creds region ~bucket ~policy () =
  S3.set_bucket_policy creds region ~bucket ~policy >>= function
    | `Ok -> print_endline "ok"; return 0
    | `AccessDenied -> print_endline "access denied"; return 1
    | `MalformedPolicy -> print_endline "malformed policy"; return 1
    | `Error msg -> print_endline msg; return 1


let _ =
  let creds =
    try
      Util.creds_of_env ()
    with Failure msg ->
      print_endline msg;
      exit 1
  in

  let command =
    match Sys.argv with
      | [| _; "delete-bucket"; region; bucket |] ->
        delete_bucket creds (S3.region_of_string region) bucket

      | [| _; "create-bucket"; region; bucket |] ->
        create_bucket creds (S3.region_of_string region) bucket

      | [| _; "get-bucket-acl"; region; bucket |] ->
        get_bucket_acl creds (S3.region_of_string region) bucket

      | [| _; "grant-bucket-permission"; region; bucket;
           grantee_aws_id; grantee_aws_display_name;
           permission
        |] ->
        grant_bucket_permission creds (S3.region_of_string region) bucket
          ~grantee_aws_id ~grantee_aws_display_name
          ~permission

      | [| _; "revoke-bucket-permission"; region; bucket;
           grantee_aws_id; grantee_aws_display_name;
           permission
        |] ->
        revoke_bucket_permission creds (S3.region_of_string region) bucket
          ~grantee_aws_id ~grantee_aws_display_name
          ~permission

      | [| _; "list-buckets"; region |] ->
        list_buckets creds (S3.region_of_string region)

      | [| _; "get-object-s"; region; bucket; objekt |] ->
        get_object_s creds (S3.region_of_string region) bucket objekt

      | [| _; "get-object"; region; bucket; objekt; path|] ->
        get_object creds (S3.region_of_string region) bucket objekt path

      | [| _; "get-object-range"; region; bucket; objekt; path; start; fini|] ->
        get_object_range creds (S3.region_of_string region) bucket objekt path
          (int_of_string start) (int_of_string fini)

      | [| _; "put-object"; region; bucket; objekt ; path |] ->
        put_object creds (S3.region_of_string region) bucket objekt path

      | [| _; "put-object-s"; region; bucket; objekt ; contents |] ->
        put_object_s creds (S3.region_of_string region) bucket objekt contents

      | [| _; "get-object-metadata"; region; bucket ; objekt |] ->
        get_object_metadata creds (S3.region_of_string region) bucket objekt

      | [| _; "list-objects"; region; bucket |] ->
        list_objects creds (S3.region_of_string region) bucket

      | [| _; "get-object-acl"; region; bucket; objekt |] ->
        get_object_acl creds (S3.region_of_string region) bucket objekt

      | [| _; "delete-object"; region; bucket; objekt |] ->
        delete_object creds (S3.region_of_string region) bucket objekt

      | [| _; "grant-object-permission"; region; bucket; objekt;
           grantee_aws_id; grantee_aws_display_name;
           permission
        |] ->
        grant_object_permission creds (S3.region_of_string region) ~bucket ~objekt
          ~grantee_aws_id ~grantee_aws_display_name
          ~permission

      | [| _; "revoke-object-permission"; region; bucket; objekt;
           grantee_aws_id; grantee_aws_display_name; permission
        |] ->
        revoke_object_permission creds (S3.region_of_string region) ~bucket ~objekt
          ~grantee_aws_id ~grantee_aws_display_name
          ~permission

      | [| _; "get-bucket-policy"; region; bucket |] ->
          get_bucket_policy creds (S3.region_of_string region) ~bucket

      | [| _; "delete-bucket-policy"; region; bucket |] ->
          delete_bucket_policy creds (S3.region_of_string region) ~bucket

      | [| _; "set-bucket-policy"; region; bucket; policy |] ->
          set_bucket_policy creds (S3.region_of_string region) ~bucket ~policy

      | _ ->
        print_endline "unknown command" ; exit 1

  in
  let exit_code = Lwt_unix.run (command ()) in
  exit exit_code

(* Copyright (c) 2011, barko 00336ea19fcb53de187740c490f764f4 All
   rights reserved.

   Redistribution and use in source and binary forms, with or without
   modification, are permitted provided that the following conditions are
   met:

   1. Redistributions of source code must retain the above copyright
   notice, this list of conditions and the following disclaimer.

   2. Redistributions in binary form must reproduce the above copyright
   notice, this list of conditions and the following disclaimer in the
   documentation and/or other materials provided with the
   distribution.

   3. Neither the name of barko nor the names of contributors may be used
   to endorse or promote products derived from this software without
   specific prior written permission.

   THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
   "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
   LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
   A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
   OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
   SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
   LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
   DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
   THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
   (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
   OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
*)

