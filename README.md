# go-crond (Docker Repackaged)

This repository provides a repackaged Docker image for [`webdevops/go-crond`](https://github.com/webdevops/go-crond), a lightweight, container-friendly cron daemon for running scheduled jobs in cloud-native environments.

## About

- **Upstream Source:** [webdevops/go-crond](https://github.com/webdevops/go-crond)
- **Docker Image:** Built from the upstream source, with no functional changes to the application itself. The Docker image may be built using updated versions of Golang as appropriate for security and compatibility.
- **Purpose:** This repo automates the build and packaging of go-crond as a Docker image, suitable for use in CI/CD pipelines, Kubernetes, and other containerized platforms.

## Usage

Pull or build the Docker image:

```bash
# Build locally
docker build -t local/go-crond:latest .
# Or use your preferred Docker build command
```

Run the container:

```bash
docker run --rm local/go-crond:latest --version
docker run --rm local/go-crond:latest --help
```

You can mount your own crontab files or configuration as needed:

```bash
docker run --rm -v $(pwd)/crontab:/etc/crontab local/go-crond:latest
```

## Testing

This repository includes a comprehensive BATS test suite for integration, CLI, HTTP, signal, and Docker-based tests. All tests run against the Docker image to ensure container compatibility.

- See `go-crond.bats` for details on running the test suite.

## License

This repository is licensed under the GNU General Public License v2.0 (GPL-2.0). See `LICENSE` for details.

## Credits

- Original authors: [webdevops/go-crond](https://github.com/webdevops/go-crond)
- This repackaged Docker image and test suite are maintained by the amazee.io team.

## Disclaimer

This repository is not affiliated with or endorsed by the original authors. All credit for the application itself goes to the upstream maintainers. This repo only repackages the software for containerized environments and provides additional testing and automation. Where sustainable, the versions of golang used to build the image may be updated.
