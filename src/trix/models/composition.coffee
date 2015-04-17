#= require trix/models/document

{arraysAreEqual} = Trix

class Trix.Composition extends Trix.BasicObject
  constructor: (@document = new Trix.Document) ->
    @document.delegate = this
    @currentAttributes = {}

  # Snapshots

  createSnapshot: ->
    document: @getDocument()
    selectedRange: @getLocationRange()

  restoreSnapshot: ({document, selectedRange}) ->
    @document.replaceDocument(document)
    @setLocationRange(selectedRange)
    @delegate?.compositionDidRestoreSnapshot?()

  # Document delegate

  didEditDocument: (document) ->
    @delegate?.compositionDidChangeDocument?(@document)

  documentDidAddAttachment: (document, attachment) ->
    @delegate?.compositionDidAddAttachment?(attachment)

  documentDidEditAttachment: (document, attachment) ->
    @delegate?.compositionDidEditAttachment?(attachment)

  documentDidRemoveAttachment: (document, attachment) ->
    @delegate?.compositionDidRemoveAttachment?(attachment)

  # Responder protocol

  insertText: (text, {updatePosition} = updatePosition: true) ->
    position = @getPosition()
    locationRange = @getLocationRange()
    @document.insertTextAtLocationRange(text, locationRange)

    endPosition = position + text.getLength()
    endLocation = @document.locationFromPosition(endPosition)
    @setLocation(endLocation) if updatePosition

    insertedLocationRange = locationRange.copyWithEndLocation(endLocation)
    @notifyDelegateOfInsertionAtLocationRange(insertedLocationRange)

  insertBlock: (block = new Trix.Block) ->
    document = new Trix.Document [block]
    @insertDocument(document)

  insertDocument: (document = Trix.Document.fromString("")) ->
    block = @getBlock()
    locationRange = @getLocationRange()
    [startPosition, endPosition] = @document.rangeFromLocationRange(locationRange)

    if block.isEmpty() and locationRange.isCollapsed()
      endPosition += 1

    else if block.getBlockBreakPosition() is locationRange.offset
      if @document.getCharacterAtPosition(startPosition - 1) is "\n"
        startPosition -= 1

    locationRange = @document.locationRangeFromRange([startPosition, endPosition])
    @document.insertDocumentAtLocationRange(document, locationRange)

    endPosition = startPosition + document.getLength()
    endLocation = @document.locationFromPosition(endPosition)
    @setLocation(endLocation)

    insertedLocationRange = locationRange.copyWithEndLocation(endLocation)
    @notifyDelegateOfInsertionAtLocationRange(insertedLocationRange)

  insertString: (string, options) ->
    attributes = @getCurrentTextAttributes()
    text = Trix.Text.textForStringWithAttributes(string, attributes)
    @insertText(text, options)

  insertBlockBreak: ->
    position = @getPosition()
    locationRange = @getLocationRange()
    @document.insertBlockBreakAtLocationRange(locationRange)

    endPosition = position + 1
    endLocation = @document.locationFromPosition(endPosition)
    @setLocation(endLocation)

    insertedLocationRange = locationRange.copyWithEndLocation(endLocation)
    @notifyDelegateOfInsertionAtLocationRange(insertedLocationRange)

  insertLineBreak: ->
    locationRange = @getLocationRange()
    block = @document.getBlockAtIndex(locationRange.end.index)

    if block.hasAttributes()
      attributes = block.getAttributes()
      blockConfig = Trix.config.blockAttributes[block.getLastAttribute()]
      if blockConfig?.listAttribute
        if block.isEmpty()
          @removeLastBlockAttribute()
        else
          @insertBlockBreak()
      else
        text = block.text.getTextAtRange([0, locationRange.end.offset])
        switch
          # Remove block attributes
          when block.isEmpty()
            @removeLastBlockAttribute()
          # Break out of block after a newline (and remove the newline)
          when text.endsWithString("\n")
            @expandSelectionInDirection("backward")
            newBlock = block.removeLastAttribute().copyWithoutText()
            @insertBlock(newBlock)
          # Stay in the block, add a newline
          else
            @insertString("\n")
    else
      @insertString("\n")

  pasteDocument: (document) ->
    blockAttributes = @getBlock().getAttributes()
    baseBlockAttributes = document.getBaseBlockAttributes()
    trailingBlockAttributes = blockAttributes.slice(-baseBlockAttributes.length)

    if arraysAreEqual(baseBlockAttributes, trailingBlockAttributes)
      leadingBlockAttributes = blockAttributes.slice(0, -baseBlockAttributes.length)
      formattedDocument = document.copyWithBaseBlockAttributes(leadingBlockAttributes)
    else
      formattedDocument = document.copyWithBaseBlockAttributes(blockAttributes)

    blockCount = formattedDocument.getBlockCount()
    firstBlock = formattedDocument.getBlockAtIndex(0)

    if blockCount is 1 and arraysAreEqual(blockAttributes, firstBlock.getAttributes())
      @insertText(firstBlock.getTextWithoutBlockBreak())
    else
      @insertDocument(formattedDocument)

  pasteHTML: (html) ->
    document = Trix.Document.fromHTML(html)
    @pasteDocument(document)

  replaceHTML: (html) ->
    document = Trix.Document.fromHTML(html).copyUsingObjectsFromDocument(@document)
    unless document.isEqualTo(@document)
      @preserveSelection =>
        @document.replaceDocument(document)

  insertFile: (file) ->
    if @delegate?.compositionShouldAcceptFile(file)
      attachment = Trix.Attachment.attachmentForFile(file)
      text = Trix.Text.textForAttachmentWithAttributes(attachment, @currentAttributes)
      @insertText(text)

  deleteInDirection: (direction) ->
    locationRange = @getLocationRange()

    if locationRange.isCollapsed()
      if direction is "backward" and locationRange.offset is 0
        if @canDecreaseBlockAttributeLevel()
          if @isEditingListItem()
            @decreaseBlockAttributeLevel() while @isEditingListItem()
          else
            @decreaseBlockAttributeLevel()
            @setLocationRange(locationRange)
            return

      range = @getExpandedRangeInDirection(direction)
      locationRange = @document.locationRangeFromRange(range)

      if direction is "backward"
        attachment = @getAttachmentAtLocationRange(locationRange)

    if attachment
      @setLocationRange(locationRange)
      @editAttachment(attachment)
    else
      @document.removeTextAtLocationRange(locationRange)
      @setLocationRange(locationRange.collapse())

  moveTextFromLocationRange: (locationRange) ->
    position = @getPosition()
    @document.moveTextFromLocationRangeToPosition(locationRange, position)
    @setPosition(position)

  removeAttachment: (attachment) ->
    if locationRange = @document.getLocationRangeOfAttachment(attachment)
      @stopEditingAttachment()
      @document.removeTextAtLocationRange(locationRange)
      @setLocationRange(locationRange.collapse())

  removeLastBlockAttribute: ->
    locationRange = @getLocationRange()
    block = @document.getBlockAtIndex(locationRange.end.index)
    @removeCurrentAttribute(block.getLastAttribute())
    @setLocationRange(locationRange.collapse())

  # Current attributes

  hasCurrentAttribute: (attributeName) ->
    @currentAttributes[attributeName]?

  toggleCurrentAttribute: (attributeName) ->
    if value = not @currentAttributes[attributeName]
      @setCurrentAttribute(attributeName, value)
    else
      @removeCurrentAttribute(attributeName)

  canSetCurrentAttribute: (attributeName) ->
    switch attributeName
      when "href"
        not @selectionContainsAttachmentWithAttribute(attributeName)
      else
        true

  setCurrentAttribute: (attributeName, value) ->
    if Trix.config.blockAttributes[attributeName]
      @setBlockAttribute(attributeName, value)
      @updateCurrentAttributes()
    else
      @setTextAttribute(attributeName, value)
      @currentAttributes[attributeName] = value
      @notifyDelegateOfCurrentAttributesChange()

  setTextAttribute: (attributeName, value) ->
    return unless locationRange = @getLocationRange()
    unless locationRange.isCollapsed()
      @document.addAttributeAtLocationRange(attributeName, value, locationRange)

  setBlockAttribute: (attributeName, value) ->
    return unless locationRange = @getLocationRange()
    range = @document.rangeFromLocationRange(locationRange)
    @document.applyBlockAttributeAtLocationRange(attributeName, value, locationRange)
    @setRange(range)

  removeCurrentAttribute: (attributeName) ->
    if Trix.config.blockAttributes[attributeName]
      @removeBlockAttribute(attributeName)
      @updateCurrentAttributes()
    else
      @removeTextAttribute(attributeName)
      delete @currentAttributes[attributeName]
      @notifyDelegateOfCurrentAttributesChange()

  removeTextAttribute: (attributeName) ->
    return unless locationRange = @getLocationRange()
    unless locationRange.isCollapsed()
      @document.removeAttributeAtLocationRange(attributeName, locationRange)

  removeBlockAttribute: (attributeName) ->
    return unless locationRange = @getLocationRange()
    @document.removeAttributeAtLocationRange(attributeName, locationRange)

  increaseBlockAttributeLevel: ->
    if attribute = @getBlock()?.getLastAttribute()
      @setCurrentAttribute(attribute)

  decreaseBlockAttributeLevel: ->
    if attribute = @getBlock()?.getLastAttribute()
      @removeCurrentAttribute(attribute)

  canIncreaseBlockAttributeLevel: ->
    return unless block = @getBlock()
    return unless attribute = block.getLastAttribute()
    return unless config = Trix.config.blockAttributes[attribute]
    if config.listAttribute
      if previousBlock = @getPreviousBlock()
        previousBlock.getAttributeAtLevel(block.getAttributeLevel()) is attribute
    else
      config.nestable

  canDecreaseBlockAttributeLevel: ->
    @getBlock()?.getAttributeLevel() > 0

  isEditingListItem: ->
    if attribute = @getBlock()?.getLastAttribute()
      Trix.config.blockAttributes[attribute].listAttribute

  updateCurrentAttributes: ->
    @currentAttributes =
      if locationRange = @getLocationRange()
        @document.getCommonAttributesAtLocationRange(locationRange)
      else
        {}

    @notifyDelegateOfCurrentAttributesChange()

  getCurrentTextAttributes: ->
    attributes = {}
    attributes[key] = value for key, value of @currentAttributes when Trix.config.textAttributes[key]
    attributes

  # Selection freezing

  freezeSelection: ->
    @setCurrentAttribute("frozen", true)

  thawSelection: ->
    @removeCurrentAttribute("frozen")

  hasFrozenSelection: ->
    @hasCurrentAttribute("frozen")

  # Location range

  @proxyMethod "getSelectionManager().getLocationRange"
  @proxyMethod "getSelectionManager().setLocationRangeFromPoint"
  @proxyMethod "getSelectionManager().preserveSelection"
  @proxyMethod "getSelectionManager().locationIsCursorTarget"
  @proxyMethod "getSelectionManager().selectionIsExpanded"
  @proxyMethod "delegate?.getSelectionManager"

  getRange: ->
    locationRange = @getLocationRange()
    @document.rangeFromLocationRange(locationRange)

  setRange: (range) ->
    locationRange = @document.locationRangeFromRange(range)
    @setLocationRange(locationRange)

  getPosition: ->
    @getRange()[0]

  setPosition: (position) ->
    location = @document.locationFromPosition(position)
    @setLocation(location)

  setLocation: (location) ->
    locationRange = new Trix.LocationRange location
    @setLocationRange(locationRange)

  setLocationRange: ->
    @delegate?.compositionDidRequestLocationRange?(arguments...)

  getExpandedRangeInDirection: (direction) ->
    range = @getRange()
    if direction is "backward"
      range[0]--
    else
      range[1]++
    range

  # Selection

  setSelectionForLocationRange: ->
    @getSelectionManager().setLocationRange(arguments...)

  moveCursorInDirection: (direction) ->
    if @editingAttachment
      locationRange = @document.getLocationRangeOfAttachment(@editingAttachment)
    else
      originalLocationRange = @getLocationRange()
      expandedRange = @getExpandedRangeInDirection(direction)
      locationRange = @document.locationRangeFromRange(expandedRange)
      canEditAttachment = not locationRange.isEqualTo(originalLocationRange)

    if direction is "backward"
      @setSelectionForLocationRange(locationRange.start)
    else
      @setSelectionForLocationRange(locationRange.end)

    if canEditAttachment
      if attachment = @getAttachmentAtLocationRange(locationRange)
        @editAttachment(attachment)

  expandSelectionInDirection: (direction) ->
    range = @getExpandedRangeInDirection(direction)
    locationRange = @document.locationRangeFromRange(range)
    @setSelectionForLocationRange(locationRange)

  expandSelectionForEditing: ->
    if @hasCurrentAttribute("href")
      @expandSelectionAroundCommonAttribute("href")

  expandSelectionAroundCommonAttribute: (attributeName) ->
    locationRange = @getLocationRange()

    if locationRange.isInSingleIndex()
      {index} = locationRange
      text = @document.getTextAtIndex(index)
      textRange = [locationRange.start.offset, locationRange.end.offset]
      [left, right] = text.getExpandedRangeForAttributeAtRange(attributeName, textRange)

      @setSelectionForLocationRange([index, left], [index, right])

  selectionContainsAttachmentWithAttribute: (attributeName) ->
    if locationRange = @getLocationRange()
      for attachment in @document.getDocumentAtLocationRange(locationRange).getAttachments()
        return true if attachment.hasAttribute(attributeName)
      false

  selectionIsInCursorTarget: ->
    @editingAttachment or @locationIsCursorTarget(@getLocationRange().start)

  getSelectedDocument: ->
    if locationRange = @getLocationRange()
      @document.getDocumentAtLocationRange(locationRange)

  # Attachment editing

  editAttachment: (attachment) ->
    return if attachment is @editingAttachment
    @stopEditingAttachment()
    @editingAttachment = attachment
    @delegate?.compositionDidStartEditingAttachment(@editingAttachment)

  stopEditingAttachment: ->
    return unless @editingAttachment
    @delegate?.compositionDidStopEditingAttachment(@editingAttachment)
    delete @editingAttachment

  canEditAttachmentCaption: ->
    @editingAttachment?.isPreviewable()

  # Private

  getDocument: ->
    @document.copy()

  getPreviousBlock: ->
    if locationRange = @getLocationRange()
      {index} = locationRange
      @document.getBlockAtIndex(index - 1) if index > 0

  getBlock: ->
    if locationRange = @getLocationRange()
      @document.getBlockAtIndex(locationRange.index)

  getAttachmentAtLocationRange: (locationRange) ->
    document = @document.getDocumentAtLocationRange(locationRange)
    if document.toString() is "#{Trix.OBJECT_REPLACEMENT_CHARACTER}\n"
      document.getAttachments()[0]

  notifyDelegateOfCurrentAttributesChange: ->
    @delegate?.compositionDidChangeCurrentAttributes?(@currentAttributes)

  notifyDelegateOfInsertionAtLocationRange: (locationRange) ->
    @delegate?.compositionDidPerformInsertionAtLocationRange?(locationRange)
