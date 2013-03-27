#= require ../vendor/jquery-ui
#= require ../vendor/jquery.ui.touch-punch
#= require ../vendor/jsplumb

window.noflo = {} unless window.noflo
window.noflo.GraphEditor = {} unless window.noflo.GraphEditor

views = window.noflo.GraphEditor.views = {}

class views.Graph extends Backbone.View
  editor: null
  editorView: null
  template: '#Graph'
  router: null
  actionBar: null

  events:
    'click #save': 'save'

  initialize: (options) ->
    @router = options.router
    @graphs = options.graphs
    @openNode = options.openNode
    @closeNode = options.closeNode
    @prepareActionBar()

  prepareActionBar: ->
    @actionBar = new ActionBar
      control:
        label: @model.get 'name'
        icon: 'noflo'
        up: this.handleUp
      actions: [
        id: 'save'
        label: 'Save'
        icon: 'cloud-upload'
        action: @save
      ]
    , @

  save: ->
    jQuery.post "#{@model.url()}/commit"

  handleUp: ->
    @router.navigate '', true

  render: ->
    jQuery('body').addClass 'grapheditor'
    template = jQuery(@template).html()
    graphData = @model.toJSON()
    graphData.name = "graph #{@model.id}" unless graphData.name
    @$el.html _.template template, graphData
    @showGraphs()
    @actionBar.show()
    @

  showGraphs: ->
    container = jQuery '.nav .dropdown .graphs', @el
    container.empty()
    @graphs.each (graph) ->
      return if graph.id is @model.id
      template = jQuery('#GraphPullDown').html()
      graphData =
        name: graph.get 'name'
        url: "#graph/#{graph.id}"
      html = jQuery _.template template, graphData
      jQuery('a', html).attr 'href', graphData.url
      container.append html
    , @

  initializeEditor: ->
    @editorView = new views.GraphEditor
      model: @model
      app: @router
      
    container = jQuery '.editor', @el
    container.html @editorView.render().el
    @editorView.activate()

class views.GraphEditor extends Backbone.View
  nodeViews: null
  edgeViews: null
  jsPlumb: null
  className: 'graph'

  events:
    'click': 'graphClicked'

  initialize: (options) ->
    @nodeViews = {}
    @edgeViews = []
    @app = options?.app
    @popover = null
    @openNode = options.openNode
    @closeNode = options.closeNode

    _.bindAll @, 'renderNodes', 'renderEdges', 'renderEdge'
    @model.get('nodes').bind 'reset', @renderNodes
    @model.get('edges').bind 'edges', @renderEdges
    @model.get('edges').bind 'add', @renderEdge

  render: ->
    @$el.empty()

    @renderNodes()
    @renderEdges()
    # TODO: Render legends

    @

  renderNodes: ->
    @model.get('nodes').each @renderNode, @

  renderEdges: ->
    @model.get('edges').each (edge) ->
      @renderEdge edge
    , @

  activate: ->
    @initializePlumb()
    _.each @nodeViews, (view) ->
      view.activate @jsPlumb
    _.each @edgeViews, (view) ->
      view.activate @jsPlumb
    @bindPlumb()

  initializePlumb: ->
    # We need this for DnD
    document.onselectstart = -> false

    # FIXME: This global shouldn't be necessary
    jsPlumb.Defaults.PaintStyle =
      strokeStyle: "#33B5E5"
      outlineWidth: 1
      outlineColor: '#000000'
      lineWidth: 2

    @jsPlumb = jsPlumb.getInstance
      Connector: "StateMachine"
      PaintStyle:
        strokeStyle: "#33B5E5"
        outlineWidth: 1
        outlineColor: '#000000'
        lineWidth: 2
      DragOptions:
        cursor: "pointer"
        zIndex: 2000
    @jsPlumb.setRenderMode jsPlumb.SVG

  bindPlumb: ->
    @jsPlumb.bind 'jsPlumbConnection', (info) =>
      newEdge =
        connection: info.connection
      for nodeId, nodeView of @nodeViews
        for port, portView of nodeView.outPorts
          continue unless portView.endPoint is info.sourceEndpoint
          newEdge.from =
            node: nodeId
            port: port
        for port, portView of nodeView.inPorts
          continue unless portView.endPoint is info.targetEndpoint
          newEdge.to =
            node: nodeId
            port: port
      return unless newEdge.to and newEdge.from
      @model.get('edges').create newEdge

    @jsPlumb.bind 'jsPlumbConnectionDetached', (info) =>
      for edgeView in @edgeViews
        continue unless edgeView.connection is info.connection
        edgeView.model.destroy()

  renderNode: (node) ->
    view = new views.GraphNode
      model: node
      networkView: @
      openNode: @openNode
    @$el.append view.render().el
    @nodeViews[node.id] = view

  renderEdge: (edge) ->
    view = new views.GraphEdge
      model: edge
      networkView: @
    view.render()
    @edgeViews.push view

class views.GraphNode extends Backbone.View
  inAnchors: ["LeftMiddle", "TopLeft", "BottomLeft", "TopCenter"]
  outAnchors: ["RightMiddle", "BottomRight", "TopRight", "BottomCenter"]
  inPorts: null
  outPorts: null
  template: '#GraphNode'
  tagName: 'div'
  className: 'process'
  jsPlumb: null

  events:
    'click': 'clicked'

  initialize: (options) ->
    @inPorts = {}
    @outPorts = {}
    @openNode = options.openNode

  clicked: (event) ->
    event.stopPropagation()
    return if @beingDragged
    @openNode @model

  render: ->
    @$el.attr 'id', @model.get 'cleanId'

    @$el.addClass 'subgraph' if @model.get 'subgraph'

    if @model.has 'display'
      @$el.css
        top: @model.get('display').x
        left: @model.get('display').y

    template = jQuery(@template).html()

    templateData = @model.toJSON()
    templateData.id = templateData.cleanId unless templateData.id

    @$el.html _.template template, templateData

    @model.get('inPorts').each @renderInport, @
    @model.get('outPorts').each @renderOutport, @
    @

  renderInport: (port, index) ->
    view = new views.GraphPort
      model: port
      inPort: true
      nodeView: @
      anchor: @inAnchors[index]
    view.render()
    @inPorts[port.get('name')] = view

  renderOutport: (port, index) ->
    view = new views.GraphPort
      model: port
      inPort: false
      nodeView: @
      anchor: @outAnchors[index]
    view.render()
    @outPorts[port.get('name')] = view

  activate: (@jsPlumb) ->
    @makeDraggable @jsPlumb
    _.each @inPorts, (view) ->
      view.activate @jsPlumb
    _.each @outPorts, (view) ->
      view.activate @jsPlumb

  saveModel: ->
    @model.save()

class views.GraphPort extends Backbone.View
  endPoint: null
  inPort: false
  anchor: "LeftMiddle"
  jsPlumb: null

  portDefaults:
    endpoint: [
      'Dot'
      radius: 6
    ]
    paintStyle:
      fillStyle: '#ffffff'

  initialize: (options) ->
    @endPoint = null
    @nodeView = options?.nodeView
    @inPort = options?.inPort
    @anchor = options?.anchor

  render: -> @

  activate: (@jsPlumb) ->
    portOptions =
      isSource: true
      isTarget: false
      maxConnections: 1
      anchor: @anchor
      overlays: [
        [
          "Label"
            location: [2.5,-0.5]
            label: @model.get('name')
        ]
      ]
    if @inPort
      portOptions.isSource = false
      portOptions.isTarget = true
      portOptions.overlays[0][1].location = [-1.5, -0.5]
    if @model.get('type') is 'array'
      portOptions.endpoint = [
        'Rectangle'
        readius: 6
      ]
      portOptions.maxConnections = -1
    @endPoint = @jsPlumb.addEndpoint @nodeView.el, portOptions, @portDefaults

class views.GraphEdge extends Backbone.View
  networkView: null
  connection: null
  jsPlumb: null

  initialize: (options) ->
    @connection = null
    @networkView = options?.networkView
    if @model.has 'connection'
      @connection = @model.get 'connection'
      @model.unset 'connection'

  render: ->
    @

  activate: (@jsPlumb) ->
    return if @connection
    sourceDef = @model.get 'from'
    targetDef = @model.get 'to'

    if sourceDef.node
      outPorts = @networkView.nodeViews[sourceDef.node].outPorts
      source = outPorts[sourceDef.port].endPoint
    else
      return
    inPorts = @networkView.nodeViews[targetDef.node].inPorts
    target = inPorts[targetDef.port].endPoint
    @connection = @jsPlumb.connect
      source: source
      target: target

views.DraggableMixin =
  beingDragged: false

  makeDraggable: (@jsPlumb) ->
    @jsPlumb.draggable @el,
      start: (event, data) => @dragStart event, data
      stop: (event, data) => @dragStop event, data
    @

  dragStart: (event, data) ->
    @beingDragged = true

  dragStop: (event, data) ->
    @model.set
      display:
        x: data.offset.top
        y: data.offset.left
    @saveModel()

    setTimeout =>
      @beingDragged = false
    , 1

_.extend views.GraphNode::, views.DraggableMixin
