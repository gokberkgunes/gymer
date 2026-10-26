Run:
```sh
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
flet run src/main.py
```

Regression tests (use temporary data):
```sh
python -m unittest discover -s tests -v
```

Workout and rest timers recover saved running time when the app reopens. Paused
workout time stays frozen. While the app runs, elapsed time uses a monotonic
clock. Recovery uses saved timestamps, so changing the system clock while the
app is closed can affect the recovered duration. Older local timestamps also
depend on the current timezone. Android background alarms are not implemented.
