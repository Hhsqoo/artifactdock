///|
async fn main {
  let matches = @argparse.Command(
    "artifactdock",
    about="A lightweight self-hosted OCI Distribution registry",
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
  serve(store, host, port) catch {
    err => println("artifactdock stopped: \{err}")
  }
}
