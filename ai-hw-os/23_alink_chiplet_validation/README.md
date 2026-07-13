# A-Link chiplet validation

This self-contained folder holds the implemented AXI4-Lite chiplet-validation RTL, seven testbenches, assertions, behavioral stand-ins, specifications, and pass criteria.

| Path | Contents |
|---|---|
| `rtl/` | Implemented production RTL and shared skid buffer |
| `tb/` | Self-checking tests; `tb/beh/` contains temporary stand-ins |
| `sva/` | Assertions paired with each test |
| `docs/alink/` | Specifications and module pass criteria |
| `ALINK_IMPLEMENTATION_STATUS.md` | Remaining production work and required unit tests |

Run the full regression from this directory:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\run_alink_regression.ps1
```

Run one test by passing `-Module`, for example:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\run_alink_regression.ps1 -Module alink_top
```

Generated artifacts go under `build/` and are ignored by Git. A passing top-level simulation still uses functional models from `tb/beh`; production completion requires all P0/P1 items in the status document.

// END-OF-ANSWER
