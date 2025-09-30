#!/usr/bin/env bats

# Test basic go-crond functionality

setup() {
    # Check if Docker image exists
    export IMAGE_NAME="${IMAGE_NAME:-local/go-crond:latest}"
    
    # Create test directories
    mkdir -p /tmp/test-cron-output
    mkdir -p /tmp/test-crontabs
    mkdir -p /tmp/test-cron-run-parts
    # Cleanup any existing test files
    rm -f /tmp/test-cron-output/*
}

teardown() {
    # Kill any running Docker containers
    docker ps -q --filter ancestor="$IMAGE_NAME" | xargs -r docker kill || true
    sleep 1
    
    # Cleanup test files
    rm -rf /tmp/test-cron-output
    rm -rf /tmp/test-crontabs
    rm -rf /tmp/test-cron-run-parts
}

@test "go-crond shows version information" {
    run docker run --rm "$IMAGE_NAME" --version
    [ "$status" -eq 0 ]
    [[ "$output" == *"go-crond version"* ]]
}

@test "go-crond shows help information" {
    run docker run --rm "$IMAGE_NAME" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
    [[ "$output" == *"--default-user"* ]]
    [[ "$output" == *"--run-parts"* ]]
}

@test "go-crond shows version number only with --dumpversion" {
    run docker run --rm "$IMAGE_NAME" --dumpversion
    [ "$status" -eq 0 ]
    # Should only contain version number, no other text
    [[ "$output" =~ ^[0-9]+\.[0-9]+\.[0-9]+ ]]
}

@test "go-crond fails gracefully with invalid arguments" {
    run docker run --rm "$IMAGE_NAME" --invalid-option
    [ "$status" -eq 1 ]
}

@test "go-crond accepts crontab file as argument" {
    # Create a simple test crontab
    cat > /tmp/test-crontabs/simple << 'EOF'
# Test crontab
* * * * * echo "test job" >> /tmp/test-cron-output/simple.log
EOF

    chmod 644 /tmp/test-crontabs/simple

    # Start go-crond
    run timeout 5s docker run --rm \
        --name go-crond-simple \
        -v /tmp/test-crontabs:/crontabs:ro \
        -v /tmp/test-cron-output:/tmp/test-cron-output \
        --entrypoint /bin/sh \
        "$IMAGE_NAME" -c "/usr/local/bin/go-crond --allow-unprivileged /crontabs/simple"
    [ "$status" -eq 124 ]
    [[ "$output" == *"start runner with 1 jobs"* ]]
}

@test "go-crond accepts multiline crontab file as argument" {
    # Create a simple test crontab
    cat > /tmp/test-crontabs/multi << 'EOF'
# Test crontab
* * * * * echo "test job" >> /tmp/test-cron-output/simple.log
* * * * * echo "test job 2" >> /tmp/test-cron-output/simple.log
EOF

    chmod 644 /tmp/test-crontabs/multi

    # Start go-crond
    run timeout 5s docker run --rm \
        --name go-crond-multi \
        -v /tmp/test-crontabs:/crontabs:ro \
        -v /tmp/test-cron-output:/tmp/test-cron-output \
        --entrypoint /bin/sh \
        "$IMAGE_NAME" -c "/usr/local/bin/go-crond --allow-unprivileged /crontabs/multi"
    [ "$status" -eq 124 ]
    [[ "$output" == *"start runner with 2 jobs"* ]]
}

@test "go-crond handles empty crontab files" {
    touch /tmp/test-crontabs/empty
    chmod 644 /tmp/test-crontabs/empty

    # Start go-crond
    run timeout 5s docker run --rm \
        --name go-crond-empty \
        -v /tmp/test-crontabs:/crontabs:ro \
        -v /tmp/test-cron-output:/tmp/test-cron-output \
        --entrypoint /bin/sh \
        "$IMAGE_NAME" -c "/usr/local/bin/go-crond --allow-unprivileged /crontabs/empty"
    [ "$status" -eq 124 ]
    [[ "$output" == *"start runner with 0 jobs"* ]]
}

@test "go-crond ignores comment lines" {
    cat > /tmp/test-crontabs/comments << 'EOF'
# This is a comment
# Another comment
# * * * * * root echo "commented out"
* * * * * root echo "active job" >> /tmp/test-cron-output/comments.log
# Final comment
EOF
    chmod 644 /tmp/test-crontabs/comments

    # Start go-crond
    run timeout 5s docker run --rm \
        --name go-crond-comments \
        -v /tmp/test-crontabs:/crontabs:ro \
        -v /tmp/test-cron-output:/tmp/test-cron-output \
        --entrypoint /bin/sh \
        "$IMAGE_NAME" -c "/usr/local/bin/go-crond --allow-unprivileged /crontabs/comments"
    [ "$status" -eq 124 ]
    [[ "$output" == *"start runner with 1 jobs"* ]]
}

@test "go-crond executes cron job at the right time" {
    # Create a crontab that runs every minute  
    cat > /tmp/test-crontabs/execution-test << 'EOF'
* * * * * root echo "$(date): job executed" >> /tmp/test-cron-output/execution.log
EOF
    chmod 644 /tmp/test-crontabs/execution-test

    # Start go-crond
    timeout 2s docker run --rm -d \
        --name go-crond-execution-test \
        -v /tmp/test-crontabs:/crontabs:ro \
        -v /tmp/test-cron-output:/tmp/test-cron-output \
        --entrypoint /bin/sh \
        "$IMAGE_NAME" -c "/usr/local/bin/go-crond --allow-unprivileged /crontabs/execution-test"
    sleep 5

    # Check the correct number of jobs have been added
    run docker logs go-crond-execution-test
    [ "$status" -eq 0 ]
    [[ "$output" == *"start runner with 1 jobs"* ]]
    
    # Wait up to 70 seconds for the file to be created
    for i in {1..70}; do
        [ -f /tmp/test-cron-output/execution.log ] && break
        sleep 1
    done
    [ -f /tmp/test-cron-output/execution.log ]
    cat /tmp/test-cron-output/execution.log | grep "job executed"

    docker kill go-crond-execution-test
}

@test "go-crond executes multiple jobs correctly" {
    cat > /tmp/test-crontabs/multi-execution << 'EOF'
* * * * * root echo "job1: $(date)" >> /tmp/test-cron-output/job1.log
* * * * * root echo "job2: $(date)" >> /tmp/test-cron-output/job2.log
EOF
    chmod 644 /tmp/test-crontabs/multi-execution

    timeout 2s docker run --rm -d \
        --name go-crond-multi-execution-test \
        -v /tmp/test-crontabs:/crontabs:ro \
        -v /tmp/test-cron-output:/tmp/test-cron-output \
        --entrypoint /bin/sh \
        "$IMAGE_NAME" -c "/usr/local/bin/go-crond --allow-unprivileged /crontabs/multi-execution"
    sleep 5
    
    # Check the correct number of jobs have been added
    run docker logs go-crond-multi-execution-test
    [ "$status" -eq 0 ]
    [[ "$output" == *"start runner with 2 jobs"* ]]

    # Wait up to 70 seconds for the file to be created
    for i in {1..70}; do
        [ -f /tmp/test-cron-output/job2.log ] && break
        sleep 1
    done
    [ -f /tmp/test-cron-output/job2.log ]
    grep "job1" /tmp/test-cron-output/job1.log
    grep "job2" /tmp/test-cron-output/job2.log

    docker kill go-crond-multi-execution-test
}

@test "go-crond executes scripts with proper environment" {
    # Create a script that outputs environment info
    cat > /tmp/test-crontabs/env-test << 'EOF'
* * * * * root env | sort >> /tmp/test-cron-output/env.log
EOF
    chmod 644 /tmp/test-crontabs/env-test

    timeout 2s docker run --rm -d \
        --name go-crond-env-test \
        -v /tmp/test-crontabs:/crontabs:ro \
        -v /tmp/test-cron-output:/tmp/test-cron-output \
        -e CUSTOM_VAR=test_value \
        --entrypoint /bin/sh \
        "$IMAGE_NAME" -c "/usr/local/bin/go-crond --allow-unprivileged /crontabs/env-test"
    sleep 5
    
    # Check the correct number of jobs have been added
    run docker logs go-crond-env-test
    [ "$status" -eq 0 ]
    [[ "$output" == *"start runner with 1 jobs"* ]]

    # Wait up to 70 seconds for the file to be created
    for i in {1..70}; do
        [ -f /tmp/test-cron-output/env.log ] && break
        sleep 1
    done
    [ -f /tmp/test-cron-output/env.log ]
    grep "CUSTOM_VAR=test_value" /tmp/test-cron-output/env.log
    docker kill go-crond-env-test
}

@test "go-crond handles failing jobs gracefully" {
    cat > /tmp/test-crontabs/failing-job << 'EOF'
* * * * * root /bin/false
* * * * * root echo "this should still run" >> /tmp/test-cron-output/after-failure.log
EOF
    chmod 644 /tmp/test-crontabs/failing-job

    timeout 2s docker run --rm -d \
        --name go-crond-failing-test \
        -v /tmp/test-crontabs:/crontabs:ro \
        -v /tmp/test-cron-output:/tmp/test-cron-output \
        --entrypoint /bin/sh \
        "$IMAGE_NAME" -c "/usr/local/bin/go-crond --allow-unprivileged /crontabs/failing-job"
    sleep 5
    
    # Check the correct number of jobs have been added
    run docker logs go-crond-failing-test
    [ "$status" -eq 0 ]
    [[ "$output" == *"start runner with 2 jobs"* ]]

    # Wait up to 70 seconds for the file to be created
    for i in {1..70}; do
        [ -f /tmp/test-cron-output/after-failure.log ] && break
        sleep 1
    done
    [ -f /tmp/test-cron-output/after-failure.log ]
    grep "this should still run" /tmp/test-cron-output/after-failure.log

    docker kill go-crond-failing-test
}

@test "go-crond respects different cron schedule formats" {
    cat > /tmp/test-crontabs/schedule-formats << 'EOF'
# Traditional 5-field format
0 1 * * * root echo "at 1am" >> /tmp/test-cron-output/1am.log

# @every format
@every 1h root echo "every hour" >> /tmp/test-cron-output/every-hour.log
@every 30s root echo "every 30 seconds" >> /tmp/test-cron-output/every-30s.log
EOF
    chmod 644 /tmp/test-crontabs/schedule-formats

    timeout 2s docker run --rm -d \
        --name go-crond-schedule-test \
        -v /tmp/test-crontabs:/crontabs:ro \
        -v /tmp/test-cron-output:/tmp/test-cron-output \
        --entrypoint /bin/sh \
        "$IMAGE_NAME" -c "/usr/local/bin/go-crond --allow-unprivileged /crontabs/schedule-formats"
    sleep 5
    
    # Check the correct number of jobs have been added
    run docker logs go-crond-schedule-test
    [ "$status" -eq 0 ]
    [[ "$output" == *"start runner with 3 jobs"* ]]
    
    # Wait up to 70 seconds for the file to be created
    for i in {1..70}; do
        [ -f /tmp/test-cron-output/every-30s.log ] && break
        sleep 1
    done
    [ -f /tmp/test-cron-output/every-30s.log ]
    grep "every 30 seconds" /tmp/test-cron-output/every-30s.log

    docker kill go-crond-schedule-test
}

@test "go-crond handles complex shell commands" {
    cat > /tmp/test-crontabs/complex-commands << 'EOF'
* * * * * root for i in 1 2 3; do echo "iteration $i" >> /tmp/test-cron-output/loop.log; done
* * * * * root if [ -f /tmp/test-file ]; then echo "file exists"; else echo "file does not exist"; fi >> /tmp/test-cron-output/conditional.log
* * * * * root echo "pipe test" | cat >> /tmp/test-cron-output/pipe.log
EOF
    chmod 644 /tmp/test-crontabs/complex-commands

    timeout 2s docker run --rm -d \
        --name go-crond-complex-test \
        -v /tmp/test-crontabs:/crontabs:ro \
        -v /tmp/test-cron-output:/tmp/test-cron-output \
        --entrypoint /bin/sh \
        "$IMAGE_NAME" -c "/usr/local/bin/go-crond --allow-unprivileged /crontabs/complex-commands"
    sleep 5
    
    # Check the correct number of jobs have been added
    run docker logs go-crond-complex-test
    [ "$status" -eq 0 ]
    [[ "$output" == *"start runner with 3 jobs"* ]]

    # Wait up to 70 seconds for the file to be created
    for i in {1..70}; do
        [ -f /tmp/test-cron-output/pipe.log ] && break
        sleep 1
    done
    [ -f /tmp/test-cron-output/pipe.log ]
    grep "iteration" /tmp/test-cron-output/loop.log
    grep  "file does not exist" /tmp/test-cron-output/conditional.log
    grep "pipe test" /tmp/test-cron-output/pipe.log

    docker kill go-crond-complex-test
}

@test "go-crond handles long-running jobs" {
    cat > /tmp/test-crontabs/long-running << 'EOF'
* * * * * root sleep 2 && echo "long job finished" >> /tmp/test-cron-output/long.log
* * * * * root echo "quick job" >> /tmp/test-cron-output/quick.log
EOF
    chmod 644 /tmp/test-crontabs/long-running

    timeout 2s docker run --rm -d \
        --name go-crond-longrun-test \
        -v /tmp/test-crontabs:/crontabs:ro \
        -v /tmp/test-cron-output:/tmp/test-cron-output \
        --entrypoint /bin/sh \
        "$IMAGE_NAME" -c "/usr/local/bin/go-crond --allow-unprivileged /crontabs/long-running"
    sleep 5
    
    # Check the correct number of jobs have been added
    run docker logs go-crond-longrun-test
    [ "$status" -eq 0 ]
    [[ "$output" == *"start runner with 2 jobs"* ]]

    # Wait up to 70 seconds for the file to be created
    for i in {1..70}; do
        [ -f /tmp/test-cron-output/long.log ] && break
        sleep 1
    done
    [ -f /tmp/test-cron-output/long.log ]
    grep "long job finished" /tmp/test-cron-output/long.log
    grep "quick job" /tmp/test-cron-output/quick.log

    docker kill go-crond-longrun-test
}

@test "go-crond supports minute --run-parts folder" {
    # Create executable script
    cat > /tmp/test-cron-run-parts/minute-test-script << 'EOF'
#!/bin/sh
echo "minute interval script executed" >> /tmp/test-cron-output/minute-runparts.log
EOF
    chmod 755 /tmp/test-cron-run-parts/minute-test-script

    timeout 2s docker run --rm -d \
        --name go-crond-runparts-minute \
        -v /tmp/test-cron-run-parts:/run-parts:ro \
        -v /tmp/test-cron-output:/tmp/test-cron-output \
        --entrypoint /bin/sh \
        "$IMAGE_NAME" -c "/usr/local/bin/go-crond --allow-unprivileged --run-parts-1min=/run-parts"
    sleep 5

    # Check the correct number of jobs have been added
    run docker logs go-crond-runparts-minute
    [ "$status" -eq 0 ]
    [[ "$output" == *"start runner with 1 jobs"* ]]

    # Wait up to 70 seconds for the file to be created
    for i in {1..70}; do
        [ -f /tmp/test-cron-output/minute-runparts.log ] && break
        sleep 1
    done
    [ -f /tmp/test-cron-output/minute-runparts.log ]
    grep "minute interval script executed" /tmp/test-cron-output/minute-runparts.log

    docker kill go-crond-runparts-minute
}

@test "go-crond supports custom --run-parts with time specification" {
    # Create executable script
    cat > /tmp/test-cron-run-parts/custom-test-script << 'EOF'
#!/bin/sh
echo "custom interval script executed" >> /tmp/test-cron-output/custom-runparts.log
EOF
    chmod 755 /tmp/test-cron-run-parts/custom-test-script

    timeout 2s docker run --rm -d \
        --name go-crond-runparts-custom \
        -v /tmp/test-cron-run-parts:/run-parts:ro \
        -v /tmp/test-cron-output:/tmp/test-cron-output \
        --entrypoint /bin/sh \
        "$IMAGE_NAME" -c "/usr/local/bin/go-crond --allow-unprivileged --run-parts=30s:/run-parts"
    sleep 5

    # Check the correct number of jobs have been added
    run docker logs go-crond-runparts-custom
    [ "$status" -eq 0 ]
    [[ "$output" == *"start runner with 1 jobs"* ]]

    # Wait up to 70 seconds for the file to be created
    for i in {1..70}; do
        [ -f /tmp/test-cron-output/custom-runparts.log ] && break
        sleep 1
    done
    [ -f /tmp/test-cron-output/custom-runparts.log ]
    grep "custom interval script executed" /tmp/test-cron-output/custom-runparts.log

    docker kill go-crond-runparts-custom
}

@test "go-crond supports --run-parts folder with multiple files" {
    # Create executable script
    cat > /tmp/test-cron-run-parts/minute-test-script << 'EOF'
#!/bin/sh
echo "minute interval script executed" >> /tmp/test-cron-output/minute-runparts.log
EOF
    chmod 755 /tmp/test-cron-run-parts/minute-test-script
    cat > /tmp/test-cron-run-parts/minute-test-script-2 << 'EOF'
#!/bin/sh
echo "another minute interval script executed" >> /tmp/test-cron-output/another-minute-runparts.log
EOF
    chmod 755 /tmp/test-cron-run-parts/minute-test-script-2

    timeout 2s docker run --rm -d \
        --name go-crond-runparts-multi \
        -v /tmp/test-cron-run-parts:/run-parts:ro \
        -v /tmp/test-cron-output:/tmp/test-cron-output \
        --entrypoint /bin/sh \
        "$IMAGE_NAME" -c "/usr/local/bin/go-crond --allow-unprivileged --run-parts-1min=/run-parts"
    sleep 5

    # Check the correct number of jobs have been added
    run docker logs go-crond-runparts-multi
    [ "$status" -eq 0 ]
    [[ "$output" == *"start runner with 2 jobs"* ]]

    # Wait up to 70 seconds for the file to be created
    for i in {1..70}; do
        [ -f /tmp/test-cron-output/another-minute-runparts.log ] && break
        sleep 1
    done
    [ -f /tmp/test-cron-output/minute-runparts.log ]
    [[ -f /tmp/test-cron-output/another-minute-runparts.log ]]
    grep "minute interval script executed" /tmp/test-cron-output/minute-runparts.log
    grep "another minute interval script executed" /tmp/test-cron-output/another-minute-runparts.log

    docker kill go-crond-runparts-multi
}
