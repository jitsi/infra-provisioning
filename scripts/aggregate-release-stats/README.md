# Introduction
The `./aggregate-release-stats.sh` will download and aggregate pre-terminate-stats for a specific release number. The results are in `pre-terminate-stats/release-${RELEASE_NUMBER}-aggregates`.

IMPORTANT: if the directory exists it WILL NOT DOWNLOAD. You can't just download the missing files, just get everything from scratch (the files are just 10KB per machine).

# Running
Run with just `./aggregate-release-stats.sh` with the necessary environment variables:

* ENVIRONMENT: required.
* RELEASE_NUMBER: required.
* REGIONS: defaults to DRG_PEER_REGIONS or a preset list.
* BUCKET_NAMESPACE: read via oracke.sh if not provided.
* DEBUG
