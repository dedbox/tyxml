type etag = string
type url_path = string list


(** This table is to store cookie values for each path. 
    The key has type url_path option: 
    it is for the path (default: root of the site),
 *)
module Cookies : Map.S
  with type key = url_path

(** This table is to store one cookie value for each cookie name. *)
module Cookievalues : Map.S
  with type key = string

(** Type used for cookies to set. 
    The float option is the timestamp for the expiration date.
    The string is the value.
 *)
type cookie = 
  | OSet of float option * string
  | OUnset

type cookieset = cookie Cookievalues.t Cookies.t

(* [add_cookie c cookie_table] adds the cookie [c] to the table [cookie_table].
   If the cookie is already bound, the previous binding disappear. *)
val add_cookie : 
    url_path -> string -> cookie -> cookieset -> cookieset

(* [add_cookies newcookies oldcookies] adds the cookies from [newcookies]
   to [oldcookies]. If cookies are already bound in oldcookies, 
   the previous binding disappear. *)
val add_cookies :
    cookie Cookievalues.t Cookies.t ->
      cookie Cookievalues.t Cookies.t -> 
        cookie Cookievalues.t Cookies.t

(* [compute_new_ri_cookies now path ri_cookies cookies_to_set] 
   adds the cookies from [cookies_to_set]
   to [ri_cookies], as if the cookies 
   add been send to the browser and the browser
   was doing a new request to the url [path]. 
   Only the cookies that match [path] (current path) are added. *)
val compute_new_ri_cookies :
    float ->
      string list ->
        string Cookievalues.t ->
          cookie Cookievalues.t Cookies.t -> string Cookievalues.t



(** The type of answers to send *)
type result =
    {res_cookies: cookieset; (** cookies to set *)
     res_lastmodified: float option; (** Default: [None] *)
     res_etag: etag option;
     res_code: int; (** HTTP code, if not 200 *)
     res_stream: string Ocsistream.t; (** Default: empty stream *)
     res_content_length: int64 option; (** [None] means Transfer-encoding: chunked *)
     res_content_type: string option;
     res_headers: Http_headers.t; (** The headers you want to add *)
     res_charset: string option; (** Default: None *)
     res_location: string option; (** Default: None *)
   }


(** Default [result] to use as a base for constructing others. *)
val default_result : unit -> result

(** [result] for an empty page. *)
val empty_result : unit -> result


module type HTTP_CONTENT =
  sig
    type t
    val result_of_content : t -> result Lwt.t
    val get_etag : t -> etag option
  end
module Http_header :
  sig
    type http_method =
        GET | POST | HEAD | PUT | DELETE | TRACE
      | OPTIONS | CONNECT | LINK | UNLINK | PATCH
    type http_mode =
        Query of (http_method * string)
      | Answer of int
      | Nofirstline
    type proto = HTTP10 | HTTP11
    type http_header = {
      mode : http_mode;
      proto : proto;
      headers : Http_headers.t;
    }
    val get_firstline : http_header -> http_mode
    val get_headers : http_header -> Http_headers.t
    val get_headers_value : http_header -> Http_headers.name -> string
    val get_headers_values : http_header -> Http_headers.name -> string list
    val get_proto : http_header -> proto
    val add_headers : http_header -> Http_headers.name -> string -> http_header
  end
module Http_error :
  sig
    exception Http_exception of int * string option
    val expl_of_code : int -> string
    val display_http_exception : exn -> unit
    val string_of_http_exception : exn -> string
  end
type t =
  { header : Http_header.http_header;
    content : string Ocsistream.t option }