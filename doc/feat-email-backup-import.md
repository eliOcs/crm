# Email Backup Import

## Overview

Allow users to import email backups (PST files) via the web UI for cases where OAuth integration is not available (e.g., corporate restrictions preventing third-party app access).

## User Flow

1. Navigate to Settings page
2. See "Import Email Backup" section with instructions
3. Follow Outlook export instructions to create PST file
4. Upload PST file (up to 2GB)
5. System extracts emails and processes with enrichment
6. Real-time progress updates via Turbo Streams
7. See completion stats (imported/skipped/failed)

## Outlook Export Instructions

### Creating a PST Backup (Windows)

1. Open Outlook and go to **File** → **Open & Export** → **Import/Export**
2. Select **Export to a file** and click Next
3. Choose **Outlook Data File (.pst)** and click Next
4. Select the **Inbox** folder
5. Check **Include subfolders** if you want nested folders
6. Click **Filter** to select a date range:
   - Go to **Advanced** tab
   - Click **Field** → **Date/Time fields** → **Received**
   - Set condition: **on or after** → Enter date (e.g., 6 months ago)
   - Click **Add to List** then **OK**
7. Click Next, choose save location, click Finish
8. Repeat for **Sent Items** folder if needed

### Tips

- Export Inbox and Sent Items separately, or select parent folder with subfolders
- Smaller date ranges process faster
- PST files can be large - ensure stable internet connection
- Maximum file size: 2 GB

## Technical Architecture

### Processing Phases

```
pending → extracting → importing → completed/failed/cancelled
```

### Components

| Component | File | Description |
|-----------|------|-------------|
| Model | `app/models/pst_email_import.rb` | Tracks import progress |
| Service | `app/services/pst_extraction_service.rb` | PST → EML extraction |
| Job | `app/jobs/pst_email_import_job.rb` | Background processing |
| Controller | `app/controllers/settings_controller.rb` | Upload/cancel actions |

### Processing Details

1. **Upload**: PST file saved to `tmp/pst_uploads/` (temporary)
2. **Extract**: `readpst` converts PST → EML files
3. **Fix CIDs**: `EmlCidFixer` repairs Content-ID headers
4. **Sort**: EML files sorted by date (oldest first)
5. **Import**: Each email processed sequentially with sync enrichment
6. **Cleanup**: Temp files deleted after completion

### Critical: Sequential Processing

Emails must be processed oldest-first to build correct context:
- Contacts are created/updated from earlier emails
- Companies are linked based on email domains
- Tasks reference existing contacts

Using `enrich: :sync` ensures each email is fully processed before the next.

## Dependencies

- `pst-utils` package (Debian) or `libpst` (Arch) for `readpst` command
- Added to Dockerfile for production

## Files

### New Files
- `db/migrate/*_create_pst_email_imports.rb`
- `app/models/pst_email_import.rb`
- `lib/eml_cid_fixer.rb`
- `app/services/pst_extraction_service.rb`
- `app/jobs/pst_email_import_job.rb`
- `app/views/settings/_pst_import_status.html.erb`

### Modified Files
- `Dockerfile` - Add pst-utils
- `app/models/user.rb` - Add association
- `config/routes.rb` - Add PST routes
- `app/controllers/settings_controller.rb` - Add actions
- `app/views/settings/edit.html.erb` - Add section
- `config/locales/en.yml`, `es.yml` - Add translations
