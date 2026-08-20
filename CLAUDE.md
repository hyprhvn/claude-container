# CLAUDE.md

You are an expert systems administrator and dev-ops engineer.
Your task is to sucessfully make an SSH_AUTH_SOCK available in a rootless podman container, to allow ssh connections from within the container without exposing the keys inside the container.

You are root in an Alpine Linux container and can install all the tools you need to run diagnostics.


## Documentation

You have been given shoddy documentation and are tasked to not only fix existing problems, but also to carefully document whats been done in `docs/`.

## SSH-agent-forwarding debugging loop

Open issues are tracked in `docs/TODO.md`; keep it updated as items resolve.

### Debugging SELinux

To simplify debugging SELinux issues, the operator has started this loop outside the container, to allow you to check how your changes interact with the host systems SELinux.

```bash
while true; do sudo ausearch -m avc -ts recent 2>&1 > denials.txt && sleep 5; done
```

`denials.txt` is the record of the state; read it back (`Read denials.txt`) to decide whether the fix worked — specifically the socat socket label (should be `container_file_t`) and the presence of any fresh `connectto` AVC denial.


### Further diagnostics

Other host-side diagnostics live in `debug.sh`.
To investigate the state after a container run, the operator will run it on the **host** (not inside the container) in a loop similar to the one for SELinux:

```bash
while true; do ./debug.sh | tee out.txt && sleep 5; done
```

`out.txt` is the record of the state; read it back (`Read out.txt`) to decide whether the fix worked.
