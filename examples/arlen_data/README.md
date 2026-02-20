# ArlenData Example

This example demonstrates using Arlen's data layer without the HTTP/MVC runtime.

Build and run from repo root:

```bash
source /usr/GNUstep/System/Library/Makefiles/GNUstep.sh
make test-data-layer
```

The executable (`build/arlen-data-example`) composes CTE/join/group queries and a PostgreSQL upsert snapshot using `ArlenData/ArlenData.h`.
