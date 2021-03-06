%% @copyright 2010 Mochi Media, Inc.

%% @doc MochiWeb socket - wrapper for plain and ssl sockets.

-module(mochiweb_socket).

-export([listen/4, accept/1, recv/3, send/2, close/1, port/1, peername/1,
         setopts/2, type/1]).

-define(ACCEPT_TIMEOUT, 2000).
-define(SSL_TIMEOUT, 10000).
-define(SSL_HANDSHAKE_TIMEOUT, 20000).


listen(Ssl, Port, Opts, SslOpts) ->
    case Ssl of
        true ->
            Opts1 = add_unbroken_ciphers_default(Opts ++ SslOpts),
            Opts2 = add_safe_protocol_versions(Opts1),
            case ssl:listen(Port, Opts2) of
                {ok, ListenSocket} ->
                    {ok, {ssl, ListenSocket}};
                {error, _} = Err ->
                    Err
            end;
        false ->
            gen_tcp:listen(Port, Opts)
    end.

add_unbroken_ciphers_default(Opts) ->
    Default = filter_unsecure_cipher_suites(ssl:cipher_suites()),
    Ciphers = filter_broken_cipher_suites(proplists:get_value(ciphers, Opts, Default)),
    [{ciphers, Ciphers} | proplists:delete(ciphers, Opts)].

filter_broken_cipher_suites(Ciphers) ->
	case proplists:get_value(ssl_app, ssl:versions()) of
		"5.3" ++ _ ->
            lists:filter(fun(Suite) ->
                                 string:left(atom_to_list(element(1, Suite)), 4) =/= "ecdh"
                         end, Ciphers);
        _ ->
            Ciphers
    end.

filter_unsecure_cipher_suites(Ciphers) ->
    lists:filter(fun
                    ({_,des_cbc,_}) -> false;
                    ({_,_,md5}) -> false;
                    (_) -> true
                 end,
                 Ciphers).

add_safe_protocol_versions(Opts) ->
    case proplists:is_defined(versions, Opts) of
        true ->
            Opts;
        false ->
            Versions = filter_unsafe_protcol_versions(proplists:get_value(available, ssl:versions())),
            [{versions, Versions} | Opts]
    end.

filter_unsafe_protcol_versions(Versions) ->
    lists:filter(fun
                    (sslv3) -> false;
                    (_) -> true
                 end,
                 Versions).


accept({ssl, ListenSocket}) ->
    % There's a bug in ssl:transport_accept/2 at the moment, which is the
    % reason for the try...catch block. Should be fixed in OTP R14.
    try ssl:transport_accept(ListenSocket, ?SSL_TIMEOUT) of
        {ok, Socket} ->
            case ssl:ssl_accept(Socket, ?SSL_HANDSHAKE_TIMEOUT) of
                ok ->
                    {ok, {ssl, Socket}};
                {error, _} = Err ->
                    Err
            end;
        {error, _} = Err ->
            Err
    catch
        error:{badmatch, {error, Reason}} ->
            {error, Reason}
    end;
accept(ListenSocket) ->
    gen_tcp:accept(ListenSocket, ?ACCEPT_TIMEOUT).

recv({ssl, Socket}, Length, Timeout) ->
    ssl:recv(Socket, Length, Timeout);
recv(Socket, Length, Timeout) ->
    gen_tcp:recv(Socket, Length, Timeout).

send({ssl, Socket}, Data) ->
    ssl:send(Socket, Data);
send(Socket, Data) ->
    gen_tcp:send(Socket, Data).

close({ssl, Socket}) ->
    ssl:close(Socket);
close(Socket) ->
    gen_tcp:close(Socket).

port({ssl, Socket}) ->
    case ssl:sockname(Socket) of
        {ok, {_, Port}} ->
            {ok, Port};
        {error, _} = Err ->
            Err
    end;
port(Socket) ->
    inet:port(Socket).

peername({ssl, Socket}) ->
    ssl:peername(Socket);
peername(Socket) ->
    inet:peername(Socket).

setopts({ssl, Socket}, Opts) ->
    ssl:setopts(Socket, Opts);
setopts(Socket, Opts) ->
    inet:setopts(Socket, Opts).

type({ssl, _}) ->
    ssl;
type(_) ->
    plain.

