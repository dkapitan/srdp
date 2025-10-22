import marimo as mo

app = mo.App()


@app.cell
def __():
    import marimo as mo

    return (mo,)


@app.cell
def __(mo):
    slider = mo.ui.slider(start=1, stop=10, label="Value:")
    return (slider,)


@app.cell
def __(mo, slider):
    mo.md(
        f"""
        # My Marimo Dashboard
        This is a simple interactive app.

        {slider}

        The slider's value is **{slider.value}**. Its square is {slider.value**2}.
        """
    )
    return


if __name__ == "__main__":
    app.run()
