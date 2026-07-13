use clap::CommandFactory;
use clap::Parser;
use std::process;

mod client;
mod cmds;
mod output;

use client::LanluApiClient;
use output::OutputMode;

#[derive(Parser)]
#[command(name = "lanlu-cli", version = "1.0.0")]
#[command(about = "Lanlu command line client")]
struct Cli {
    /// Output mode: text|json|pretty-json (default: text)
    #[arg(short = 'o', long = "output", default_value = "text")]
    output: String,

    /// Ignore http_proxy / https_proxy environment variables
    #[arg(long = "no-proxy")]
    no_proxy: bool,

    #[command(subcommand)]
    command: Option<Commands>,
}

#[derive(Parser)]
enum Commands {
    /// Server info
    Info,
    /// Search archives
    Search {
        /// Search filter query
        filter: Option<String>,
        /// Category ID
        #[arg(long)]
        category: Option<String>,
        /// Page number
        #[arg(long)]
        page: Option<String>,
        /// Page size
        #[arg(long = "page-size")]
        page_size: Option<String>,
        /// Sort by field
        #[arg(long)]
        sortby: Option<String>,
        /// Sort order
        #[arg(long)]
        order: Option<String>,
        /// New only
        #[arg(long = "new-only")]
        new_only: bool,
        /// Untagged only
        #[arg(long = "untagged-only")]
        untagged_only: bool,
        /// Favorite only
        #[arg(long = "favorite-only")]
        favorite_only: bool,
        /// Group by tankoubon collections
        #[arg(long = "group-by-tanks")]
        group_by_tanks: bool,
    },
    /// Show archive metadata
    #[command(name = "archive-show")]
    ArchiveShow {
        /// Archive ID
        arcid: String,
        /// Include pages
        #[arg(long = "include-pages")]
        include_pages: bool,
    },
    /// List categories
    #[command(name = "category-list")]
    CategoryList,
    /// Show cover asset_id or URL
    Cover {
        /// Archive or tankoubon ID
        id: Option<String>,
        /// Show URL for a known asset_id
        #[arg(long = "asset-id")]
        asset_id: Option<String>,
    },
    /// List tankoubon collections
    #[command(name = "tankoubon-list")]
    TankoubonList,
    /// Show tankoubon detail + archives
    #[command(name = "tankoubon-show")]
    TankoubonShow {
        /// Tankoubon ID
        id: String,
    },
    /// Update metadata
    #[command(name = "update-metadata")]
    UpdateMetadata {
        /// Target ID (archive or tankoubon)
        id: String,
        /// New title
        #[arg(long)]
        title: Option<String>,
        /// New description
        #[arg(long)]
        description: Option<String>,
        /// New tags (comma-separated or JSON array)
        #[arg(long)]
        tags: Option<String>,
        /// Release date
        #[arg(long = "release-at")]
        release_at: Option<String>,
        /// Cover asset ID
        #[arg(long)]
        cover: Option<String>,
        /// Target type: archive or tankoubon
        #[arg(long = "target-type", default_value = "archive")]
        target_type: String,
        /// Metadata namespace
        #[arg(long)]
        namespace: Option<String>,
    },
    /// List source plugins
    #[command(name = "source-list")]
    SourceList,
    /// Source plugin home page
    #[command(name = "source-home")]
    SourceHome {
        /// Plugin namespace
        namespace: String,
    },
    /// Search source plugin
    #[command(name = "source-search")]
    SourceSearch {
        /// Plugin namespace
        namespace: String,
        /// Search query
        query: Option<String>,
        /// Page number
        #[arg(long)]
        page: Option<String>,
        /// Filters JSON
        #[arg(long)]
        filters: Option<String>,
    },
    /// Get source plugin filters
    #[command(name = "source-filters")]
    SourceFilters {
        /// Plugin namespace
        namespace: String,
    },
    /// Download from source plugin
    #[command(name = "source-download")]
    SourceDownload {
        /// Plugin namespace
        namespace: String,
        /// Remote item ID
        #[arg(name = "remote-id")]
        remote_id: String,
        /// Target category ID (required)
        #[arg(long = "category-id", required = true)]
        category_id: String,
        /// Item kind
        #[arg(long, default_value = "archive")]
        kind: String,
        /// Wait for task completion
        #[arg(long)]
        wait: bool,
        /// Poll interval in ms
        #[arg(long, default_value = "1000")]
        interval: u64,
        /// Timeout in ms
        #[arg(long, default_value = "300000")]
        timeout: u64,
    },
    /// Download from URL
    #[command(name = "download-url")]
    DownloadUrl {
        /// URL to download
        url: String,
        /// Target category ID (required)
        #[arg(long = "category-id", required = true)]
        category_id: String,
        /// Wait for task completion
        #[arg(long)]
        wait: bool,
        /// Poll interval in ms
        #[arg(long, default_value = "1000")]
        interval: u64,
        /// Timeout in ms
        #[arg(long, default_value = "300000")]
        timeout: u64,
    },
    /// Upload file
    Upload {
        /// File path to upload
        file: String,
        /// Target category ID (required)
        #[arg(long = "category-id", required = true)]
        category_id: String,
        /// Chunk size in bytes
        #[arg(long = "chunk-size", default_value = "8388608")]
        chunk_size: usize,
        /// Target type
        #[arg(long = "target-type", default_value = "archive")]
        target_type: String,
        /// Overwrite if exists
        #[arg(long)]
        overwrite: bool,
        /// Wait for task completion
        #[arg(long)]
        wait: bool,
        /// Poll interval in ms
        #[arg(long, default_value = "1000")]
        interval: u64,
        /// Timeout in ms
        #[arg(long, default_value = "300000")]
        timeout: u64,
    },
    /// Run metadata plugin
    #[command(name = "metadata-run")]
    MetadataRun {
        /// Plugin namespace
        namespace: String,
        /// Target ID
        #[arg(name = "target-id")]
        target_id: String,
        /// Target type
        #[arg(long = "target-type", default_value = "archive")]
        target_type: String,
        /// Plugin parameter
        #[arg(long)]
        param: Option<String>,
        /// Write back results
        #[arg(long = "write-back")]
        write_back: bool,
        /// Wait for task completion
        #[arg(long)]
        wait: bool,
        /// Poll interval in ms
        #[arg(long, default_value = "1000")]
        interval: u64,
        /// Timeout in ms
        #[arg(long, default_value = "300000")]
        timeout: u64,
    },
    /// Show task detail
    Task {
        /// Task ID
        id: String,
    },
}

#[tokio::main]
async fn main() {
    let cli = Cli::parse();

    let output_mode = if ["json", "pretty-json"].contains(&cli.output.as_str()) {
        OutputMode::from_str(&cli.output)
    } else {
        OutputMode::Text
    };

    // Check for command or help
    let cmd = match &cli.command {
        Some(c) => c,
        None => {
            // Print help if no command
            let mut cmd = Cli::command();
            cmd.print_help().unwrap();
            println!();
            process::exit(0);
        }
    };

    let token = match std::env::var("LANLU_TOKEN") {
        Ok(t) if !t.is_empty() => t,
        _ => {
            eprintln!("LANLU_TOKEN environment variable is required");
            process::exit(1);
        }
    };

    let host = std::env::var("LANLU_HOST").unwrap_or_else(|_| "http://localhost:8082".to_string());
    let client = LanluApiClient::new(host, token, cli.no_proxy);

    let result = match cmd {
        Commands::Info => cmds::info::handle_info(&client, output_mode).await,
        Commands::Search {
            filter,
            category,
            page,
            page_size,
            sortby,
            order,
            new_only,
            untagged_only,
            favorite_only,
            group_by_tanks,
        } => {
            let f = filter.as_deref().unwrap_or("");
            cmds::search::handle_search(
                &client,
                f,
                category.as_deref(),
                page.as_deref(),
                page_size.as_deref(),
                sortby.as_deref(),
                order.as_deref(),
                *new_only,
                *untagged_only,
                *favorite_only,
                *group_by_tanks,
                output_mode,
            )
            .await
        }
        Commands::ArchiveShow {
            arcid,
            include_pages,
        } => {
            cmds::search::handle_archive_show(&client, arcid, *include_pages, output_mode).await
        }
        Commands::CategoryList => cmds::search::handle_category_list(&client, output_mode).await,
        Commands::Cover { id, asset_id } => {
            cmds::cover::handle_cover(&client, id.as_deref(), asset_id.as_deref(), output_mode)
                .await
        }
        Commands::TankoubonList => cmds::tankoubon::handle_tankoubon_list(&client, output_mode).await,
        Commands::TankoubonShow { id } => {
            cmds::tankoubon::handle_tankoubon_show(&client, id, output_mode).await
        }
        Commands::UpdateMetadata {
            id,
            title,
            description,
            tags,
            release_at,
            cover,
            target_type,
            namespace,
        } => {
            cmds::metadata::handle_update_metadata(
                &client,
                id,
                target_type,
                title.as_deref(),
                description.as_deref(),
                tags.as_deref(),
                release_at.as_deref(),
                cover.as_deref(),
                namespace.as_deref(),
                output_mode,
            )
            .await
        }
        Commands::SourceList => cmds::source::handle_source_list(&client, output_mode).await,
        Commands::SourceHome { namespace } => {
            cmds::source::handle_source_home(&client, namespace, output_mode).await
        }
        Commands::SourceSearch {
            namespace,
            query,
            page,
            filters,
        } => {
            cmds::source::handle_source_search(
                &client,
                namespace,
                query.as_deref().unwrap_or(""),
                page.as_deref(),
                filters.as_deref(),
                output_mode,
            )
            .await
        }
        Commands::SourceFilters { namespace } => {
            cmds::source::handle_source_filters(&client, namespace, output_mode).await
        }
        Commands::SourceDownload {
            namespace,
            remote_id,
            category_id,
            kind,
            wait,
            interval,
            timeout,
        } => {
            cmds::source::handle_source_download(
                &client,
                namespace,
                remote_id,
                category_id,
                kind,
                *wait,
                *interval,
                *timeout,
                output_mode,
            )
            .await
        }
        Commands::DownloadUrl {
            url,
            category_id,
            wait,
            interval,
            timeout,
        } => {
            cmds::download_upload::handle_download_url(
                &client,
                url,
                category_id,
                *wait,
                *interval,
                *timeout,
                output_mode,
            )
            .await
        }
        Commands::Upload {
            file,
            category_id,
            chunk_size,
            target_type,
            overwrite,
            wait,
            interval,
            timeout,
        } => {
            cmds::download_upload::handle_upload(
                &client,
                file,
                category_id,
                *chunk_size,
                target_type,
                *overwrite,
                *wait,
                *interval,
                *timeout,
                output_mode,
            )
            .await
        }
        Commands::MetadataRun {
            namespace,
            target_id,
            target_type,
            param,
            write_back,
            wait,
            interval,
            timeout,
        } => {
            cmds::download_upload::handle_metadata_run(
                &client,
                namespace,
                target_id,
                target_type,
                param.as_deref().unwrap_or(""),
                *write_back,
                *wait,
                *interval,
                *timeout,
                output_mode,
            )
            .await
        }
        Commands::Task { id } => cmds::task::handle_task(&client, id, output_mode).await,
    };

    if let Err(e) = result {
        eprintln!("error: {}", e);
        process::exit(1);
    }
}
