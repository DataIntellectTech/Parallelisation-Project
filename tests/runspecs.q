// load qutil the way its sample q.q does (we can't edit the shared KDB-X q.q), then run qspec's runner
// usage (from the repo root): q tests/runspecs.q -q <spec file or folder> [--fail-fast] [--desc] ...
{[envvar]
  sep:$["w"~first string .z.o;";";":"];
  .utl.QPATH:hsym each `$sep vs getenv envvar;
  b:` sv' .utl.QPATH,'`bootstrap.q;
  system "l ",1_string first b where 0<count each key each b;
 }[`QPATH];

system "l tests/spec.q";
