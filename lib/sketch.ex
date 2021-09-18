defmodule Sketch do
  defstruct title: "Sketch",
            width: 800,
            height: 600,
            items: %{},
            order: [],
            background: Sketch.Color.new({255, 255, 255})

  @type t :: %Sketch{
          title: String.t(),
          width: number,
          height: number,
          background: Sketch.Color.t(),
          items: map,
          order: [integer()]
        }

  @type coordinates :: {number, number}

  @moduledoc """

  """

  @doc """
    Create a new Sketch
  """
  @spec new(opts :: list) :: Sketch.t()
  def new(opts \\ []) do
    background = Keyword.get(opts, :background, {255, 255, 255}) |> Sketch.Color.new()

    %__MODULE__{
      title: Keyword.get(opts, :title, "Sketch"),
      width: Keyword.get(opts, :width, 800),
      height: Keyword.get(opts, :height, 600),
      background: background
    }
  end

  @doc """
  Open a window to show the drawn sketch (using wxWidgets)
  """
  def run(%Sketch{} = sketch) do
    Sketch.Runner.start_link(sketch)
  end

  @spec save(Sketch.t()) :: %{:dirty => %{}, :operations => [], optional(any) => any}
  def save(%Sketch{} = sketch) do
    image =
      %Mogrify.Image{path: "#{sketch.title}.png", ext: "png"}
      |> Mogrify.custom("size", "#{sketch.width}x#{sketch.height}")
      |> Mogrify.canvas(Sketch.Color.to_hex(sketch.background))
      |> Mogrify.custom("stroke", "black")

    complete =
      Enum.reverse(sketch.order)
      |> Enum.reduce(image, fn id, image ->
        case Map.get(sketch.items, id) do
          %{type: :fill, color: color} ->
            Mogrify.custom(image, "fill", Sketch.Color.to_hex(color))

          %{type: :translate, dx: dx, dy: dy} ->
            Mogrify.custom(image, "draw", "translate #{dx},#{dy}")

          shape ->
            Sketch.Primitives.Render.render_png(shape, image)
        end
      end)

    try do
      Mogrify.create(complete, path: ".")
    rescue
      e in RuntimeError ->
        if String.match?(e.message, ~r/missing prerequisite/) do
          raise "It seems like you don't have ImageMagick installed. Try installing it with `brew install imagemagick`"
        else
          raise e
        end
    end
  end

  def example do
    Sketch.new(background: {165, 122, 222})
    |> Sketch.line(%{start: {0, 0}, finish: {100, 100}})
    |> Sketch.set_fill({200, 120, 0})
    |> Sketch.rect(%{origin: {40, 40}, width: 30, height: 30})
    |> Sketch.translate(500, 500)
    |> Sketch.set_fill({0, 120, 255})
    |> Sketch.square(%{origin: {100, 100}, size: 50})
  end

  @doc """
  Add a line to a sketch
  """
  @spec line(Sketch.t(), %{start: coordinates(), finish: coordinates()}) :: Sketch.t()
  def line(%Sketch{} = sketch, params) do
    line = Map.put(params, :id, next_id(sketch)) |> Sketch.Primitives.Line.new()

    add_item(sketch, line)
  end

  @doc """
  Add a rectangle to a sketch
  """
  @spec rect(Sketch.t(), %{origin: coordinates(), width: integer(), height: integer()}) ::
          Sketch.t()
  def rect(sketch, params) do
    rect = Map.put(params, :id, next_id(sketch)) |> Sketch.Primitives.Rect.new()

    add_item(sketch, rect)
  end

  @doc """
  Add a square to a sketch. This is not meaningfullly different from adding a rectangle with the same width and height,
  but is a convenience function for readability.
  """
  @spec square(Sketch.t(), %{origin: coordinates(), size: integer()}) ::
          Sketch.t()
  def square(%Sketch{} = sketch, params) do
    square = Map.put(params, :id, next_id(sketch)) |> Sketch.Primitives.Square.new()

    add_item(sketch, square)
  end

  @doc """
  Add any shape to a sketch. Usually it will be easier to use the helper functions for the individual primitives
  instead of using this directly, but this is exposed to allow custom shapes to be added.

  Note: custom shapes should Just Work™️, as long as they have an `:id` key, and implement the `Sketch.Render` protocol
  """
  def add_item(sketch, item) do
    items = Map.put_new(sketch.items, item.id, item)
    order = [item.id | sketch.order]
    %{sketch | items: items, order: order}
  end

  def set_fill(sketch, {_r, _g, _b} = col) do
    fill = %{type: :fill, color: Sketch.Color.new(col), id: next_id(sketch)}
    add_item(sketch, fill)
  end

  def translate(sketch, dx, dy) do
    translate = %{
      type: :translate,
      dx: dx,
      dy: dy,
      id: next_id(sketch)
    }

    add_item(sketch, translate)
  end

  defp next_id(%{order: []}), do: 1

  defp next_id(%{order: [prev | _]}) do
    prev + 1
  end
end
