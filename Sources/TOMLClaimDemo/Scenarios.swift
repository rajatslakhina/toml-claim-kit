/// An answer, and the rewrite the feedback asks for.
struct Scenario {
    let title: String
    let answer: String
    let rewrite: String
}

/// Answers an assistant might give, each with the rewrite the feedback asks for.
enum Scenarios {
    static let mypy = """
    This `pyproject.toml` is valid TOML:

    ```toml
    [project]
    name = "inventory"
    requires-python = ">=3.10"

    [tool.mypy]
    python_version = 3.10
    strict = true
    ```

    In TOML, `python_version = 3.10` is read as the string "3.10", so mypy checks against Python 3.10:

    ```python
    import tomllib

    with open("pyproject.toml", "rb") as f:
        data = tomllib.load(f)
    print(data["tool"]["mypy"]["python_version"])  # 3.10
    ```
    """

    static let mypyFixed = """
    This `pyproject.toml` is valid TOML:

    ```toml
    [project]
    name = "inventory"
    requires-python = ">=3.10"

    [tool.mypy]
    python_version = "3.10"
    strict = true
    ```

    Quoted, `python_version = "3.10"` is read as the string "3.10"; unquoted, `3.10` is read as the float `3.1`:

    ```python
    import tomllib

    with open("pyproject.toml", "rb") as f:
        data = tomllib.load(f)
    print(data["tool"]["mypy"]["python_version"])  # 3.10
    ```
    """

    static let textMode = """
    ```toml
    [tool.poetry]
    name = "inventory"
    version = "0.1.0"
    ```

    Read the version with the standard library's TOML parser:

    ```python
    import tomllib

    with open("pyproject.toml") as f:
        config = tomllib.load(f)
    ```

    Then read the version:

    ```python
    with open("pyproject.toml", "rb") as f:
        config = tomllib.load(f)
    print(config["tool.poetry"]["version"])  # 0.1.0
    ```
    """

    static let textModeFixed = """
    ```toml
    [tool.poetry]
    name = "inventory"
    version = "0.1.0"
    ```

    Read the version with the standard library's TOML parser:

    ```python
    import tomllib

    with open("pyproject.toml", "rb") as f:
        config = tomllib.load(f)
    print(config["tool"]["poetry"]["version"])  # 0.1.0
    ```
    """

    static let poetry = """
    Add the dependency section below; it is valid TOML:

    ```toml
    [tool.poetry.dependencies]
    python = ^3.10
    requests = "^2.31"
    debug = True
    ```
    """

    static let poetryFixed = """
    Add the dependency section below; it is valid TOML:

    ```toml
    [tool.poetry.dependencies]
    python = "^3.10"
    requests = "^2.31"
    debug = true
    ```
    """

    static let tables = """
    ```toml
    [server]
    host = "0.0.0.0"

    [server]
    port = 8080
    ```

    A repeated key keeps the last value, so the second line wins:

    ```python
    import tomllib
    settings = tomllib.loads('port = 8000\\nport = 8080\\n')
    print(settings["port"])  # 8080
    ```

    To save changes back, call `tomllib.dumps(settings)`:

    ```python
    import tomllib
    text = tomllib.dumps(settings)
    ```
    """

    static let tablesFixed = """
    ```toml
    [server]
    host = "0.0.0.0"
    port = 8080
    ```

    A repeated key is an error in TOML:

    ```python
    import tomllib
    settings = tomllib.loads('port = 8000\\nport = 8080\\n')  # TOMLDecodeError: Cannot overwrite a value
    ```

    `tomllib` only reads; write the file back with the tomli-w package:

    ```python
    import tomli_w
    text = tomli_w.dumps(settings)
    ```
    """

    static let readings = """
    A few TOML values, and what tomllib reads them as:

    - `timeout = 1e3` is a float.
    - `mode = 0o755` is the integer 493.
    - `released = 2024-01-02` is loaded as a `datetime.date`.
    - `mode = 0755` is the integer 755.
    - `enabled = True` is a boolean.
    - `start = 09:30` is a time.
    """
}
