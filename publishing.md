# Publishing

This checkout publishes the same 1.1.0 from three places:

| artifact        | coordinate      | where                                        |
| --------------- | --------------- | -------------------------------------------- |
| Java library    | `hr.hrg:wyhash` | Maven Central, through the Central publisher |
| JavaScript port | `@hrg/wyhash`   | npm                                          |
| Zig port        | source          | this repository (no binary release workflow) |

`pom.xml`, `pom-release.xml` and `package.json` carry `1.1.0`; `bun scripts/check-poms.mjs` asserts they agree. The
Java release must be published **before `hr.hrg:fs-meta`**, which pins `hr.hrg:wyhash:1.1.0`.

## Before the first release

1. **JDK 22 or newer** (`JAVA_HOME`). The artifact targets Java 22 because of the `MemorySegment` input; this machine
   has JDK 25 at `C:\Program Files\Java\jdk-25`.
2. **Real Maven 3.9.x, not `mvnd`.** This machine's `mvn` is `mvnd`; the gitignore checkout has an unpacked Maven at
   `..\gitignore\.tmp\maven\apache-maven-3.9.9\bin\mvn.cmd`. Any unpacked Maven 3.9.x works; the examples use
   `<maven-home>\bin\mvn.cmd`.
3. **The Central token** in `~/.m2/settings.xml`, under a server with id **`central`**. The publisher is configured
   with `publishingServerId=central`.
4. **A GPG key and `MAVEN_GPG_PASSPHRASE`.** Signing is off by default (`gpg.skip=true`); a release passes
   `-Dgpg.skip=false`. The profile passes `--pinentry-mode loopback`, so gpg reads the environment instead of opening a
   prompt a batch build cannot answer.
5. **A version and a tag.** `1.1.0` is the release; tag the released commit. `1.1.0` supersedes `1.0.0` and is the
   version fs-meta now pins.

## Publishing the Maven artifact

### Why there are two POMs

`pom.xml` is the normal build. It has no Central publisher, sets `maven.deploy.skip=true`, and a bare `mvn deploy`
therefore uploads nothing. `pom-release.xml` is a **copy** of it plus the `central-publishing-maven-plugin` in the
top-level `<build>`; it keeps `maven.deploy.skip=true`, because that stops `maven-deploy-plugin`, not the publisher (a
separate goal at the same phase). If the publisher extension ever failed to load, the release would do nothing instead
of falling back to a direct upload.

The publisher cannot live in `pom.xml`: Maven reads `<extensions>true</extensions>` only from a top-level `<build>`,
never from a profile. It cannot be a child of `pom.xml` either: Maven 3.9.9 rejects a jar-packaged POM as a parent, and
Maven has no POM include. So the file is duplicated and [scripts/check-poms.mjs](scripts/check-poms.mjs) keeps the
copies in step:

```text
bun scripts/check-poms.mjs
```

The check strips comments, removes the release-only publisher, and fails if anything else differs. It also asserts no
SNAPSHOT dependency and that the POM and npm package versions agree.

### The release commands

Build and inspect the binary, sources and javadoc jars without uploading:

```text
$env:JAVA_HOME = 'C:\Program Files\Java\jdk-25'
<maven-home>\bin\mvn.cmd -f pom-release.xml -Ppublish -DskipTests package
```

Exercise the publisher without uploading — it stages and bundles, logs
`Skipping Central Publishing at user's request.`, and stops:

```text
<maven-home>\bin\mvn.cmd -f pom-release.xml -DskipTests -DskipPublishing=true deploy
```

The release itself:

```text
$env:MAVEN_GPG_PASSPHRASE = '<your passphrase>'
<maven-home>\bin\mvn.cmd -f pom-release.xml -Ppublish -Dgpg.skip=false -DskipTests deploy
```

`-Ppublish` adds `maven-source-plugin`, `maven-javadoc-plugin` and `maven-gpg-plugin`. The Central publisher takes over
`deploy`, uses the `central` server for credentials, and publishes automatically (`autoPublish=true`).

### Common failures

| symptom                                                           | cause                                                                                     |
| ----------------------------------------------------------------- | ----------------------------------------------------------------------------------------- |
| `401` / `Unauthorized` from the publisher                         | missing or expired token under the `central` server id                                    |
| `gpg: signing failed: Bad passphrase`                             | `MAVEN_GPG_PASSPHRASE` is wrong; unset shows `Operation cancelled`                        |
| `Invalid packaging for parent POM ... must be 'pom' but is 'jar'` | `pom-release.xml` was made a child of `pom.xml`; it is a copy                             |
| `deploy` uploaded nothing                                         | that was `pom.xml` (guard) or `-DskipPublishing=true`; the release uses `pom-release.xml` |

## Publishing the npm package

npm already has an unrelated `wyhash@1.0.0` by lemon-mint, so this project's JavaScript port cannot use the bare name.
It is published as the scoped package **`@hrg/wyhash`**, with `publishConfig.access: public`; `fs-meta` imports
`@hrg/wyhash/js/wyhash64.mjs` and declares it as an optional peer.

```text
bun test js
bun pm pack --dry-run
npm publish
```

The package contains `js/wyhash64.mjs`, the conformance vectors, `WYHASH.md`, the README and the licence. A live token
that can publish to the `@hrg` scope is required; npm reports a `404` when a token cannot publish to a scope.

Publishing the npm package is what makes the Node trio reader work without a checkout link: `fs-meta`'s `layout.mjs`
loads the port dynamically when Bun's native hash is absent.

## Publishing the Zig port

The Zig port is consumed as source (`zig/`, `tests.zig`); there is no binary release workflow. Tag the same commit as the
Maven and npm release.
