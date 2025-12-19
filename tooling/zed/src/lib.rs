use zed_extension_api::{self as zed, Command, Result};

struct FerruleExtension;

impl zed::Extension for FerruleExtension {
    fn new() -> Self {
        FerruleExtension
    }

    fn language_server_command(
        &mut self,
        language_server_id: &zed::LanguageServerId,
        _worktree: &zed::Worktree,
    ) -> Result<Command> {
        if language_server_id.as_ref() == "ferrule-lsp" {
            Ok(Command {
                command: "ferrule-lsp".to_string(),
                args: vec![],
                env: Default::default(),
            })
        } else {
            Err(format!("unknown language server: {}", language_server_id.as_ref()))
        }
    }
}

zed::register_extension!(FerruleExtension);
