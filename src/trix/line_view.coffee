class Trix.LineView extends Trix.View
  constructor: (line) ->
    @element = @createElement "div", "line_view"
    @update line

  update: (@line) ->
    @refresh()

  refresh: ->
    @element.innerHTML = ""
    @element.appendChild document.createTextNode "\uFEFF" + formatLine(@line) + "\uFEFF"

  getObservedEvents: ->
    super.concat [["mousedown", @onMouseDown, true]]

  onMouseDown: (event) =>
    column = @getColumnAtPoint event.clientX, event.clientY
    @owner.lineViewClickedAtColumn this, column

  getBoundingClientRectAtColumn: (column) ->
    anteriorTextNode = @element.childNodes[0]
    columnTextNode = anteriorTextNode.splitText column + 1
    posteriorTextNode = columnTextNode.splitText 1 if columnTextNode.length > 1

    range = document.createRange()
    range.selectNodeContents(columnTextNode)
    rect = range.getClientRects()[0]

    @element.normalize()
    rect

  getColumnAtPoint: (left, top) ->
    column = @line.length

    while column >= 0
      rect = @getBoundingClientRectAtColumn column
      return column if rect.left <= left <= rect.right and rect.top <= top <= rect.bottom
      column--

    null

  formatLine = (line) ->
    line
      .replace(/^\n/, "\uFEFF")
      .replace /^ +/, (match) ->
        Array(match.length + 1).join "\u00A0"
      .replace /\ ( +)/, (match) ->
        " " + Array(match.length).join "\u00A0"