///|
async fn main {
  let matches = @argparse.Command(
    "artifactdock",
    about="A lightweight self-hosted OCI Distribution registry",
    flags=[
      @argparse.FlagArg(
        "gc",
        long="gc",
        about="run offline garbage collection and exit",
      ),
      @argparse.FlagArg(
        "dry_run",
        long="dry-run",
        about="report reclaimable content without deleting it",
        requires=["gc"],
      ),
    ],
    options=[
      @argparse.OptionArg(
        "root",
        short='r',
        default_values=["./artifactdock-data"],
        about="filesystem storage root",
      ),
      @argparse.OptionArg(
        "host",
        default_values=["127.0.0.1"],
        about="listen host",
      ),
      @argparse.OptionArg(
        "port",
        short='p',
        default_values=["5000"],
        about="listen port",
      ),
    ],
  ).parse()
  let root = matches.values["root"][0]
  let host = matches.values["host"][0]
  let port = @string.parse_int(matches.values["port"][0]) catch { _ => 5000 }
  let store = RegistryStore::new(root)
  let gc = match matches.flags.get("gc") {
    Some(value) => value
    None => false
  }
  let dry_run = match matches.flags.get("dry_run") {
    Some(value) => value
    None => false
  }
  if gc {
    store.ensure()
    let (scanned, reclaimable, bytes) = store.collect_garbage(dry_run)
    let mode = if dry_run { "dry run" } else { "complete" }
    println(
      "garbage collection \{mode}: scanned=\{scanned} reclaimable=\{reclaimable} bytes=\{bytes}",
    )
    return
  }
  serve(store, host, port) catch {
    err => println("artifactdock stopped: \{err}")
  }
}
