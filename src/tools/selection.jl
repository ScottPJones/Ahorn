module Selection

displayName = "Selection"
group = "Placements"

drawingLayers = Main.Layer[]

toolsLayer = nothing
targetLayer = nothing

# Drag selection, track individually for easy replacement
selectionRect = Main.Rectangle(0, 0, 0, 0)
selections = Set{Tuple{String, Main.Rectangle, Any, Number}}[]

lastX, lastY = -1, -1
shouldDrag = true

decalScaleVals = (1.0, 2.0^4)

function drawSelections(layer::Main.Layer, room::Main.Room)
    drawnTargets = Set()
    ctx = Main.creategc(toolsLayer.surface)

    if selectionRect !== nothing && selectionRect.w > 0 && selectionRect.h > 0 && !shouldDrag
        Main.drawRectangle(ctx, selectionRect, Main.colors.selection_selection_fc, Main.colors.selection_selection_bc)
    end

    for selection in selections
        layer, box, target, node = selection

        if isa(target, Main.Maple.Entity) && !(target in drawnTargets)
            Main.renderEntitySelection(ctx, toolsLayer, target, Main.loadedState.room)

            push!(drawnTargets, target)
        end

        if isa(target, Main.TileSelection)
            Main.drawFakeTiles(ctx, Main.loadedState.room, target.tiles, target.fg, target.selection.x, target.selection.y, clipEdges=true)
        end

        # Get a new selection rectangle
        # This is easier than editing the existing rect
        success, rect = Main.getSelection(target)
        if isa(rect, Array{Main.Rectangle}) && length(rect) >= node + 1
            Main.drawRectangle(ctx, rect[node + 1], Main.colors.selection_selected_fc, Main.colors.selection_selected_bc)

        else
            Main.drawRectangle(ctx, rect, Main.colors.selection_selected_fc, Main.colors.selection_selected_bc)
        end
    end

    return true
end

function clearDragging!()
    global lastX = -1
    global lastY = -1
    global shouldDrag = false
end

function cleanup()
    finalizeSelections!(selections)
    empty!(selections)
    global selectionRect = nothing
    clearDragging!()

    Main.redrawLayer!(toolsLayer)
end

function toolSelected(subTools::Main.ListContainer, layers::Main.ListContainer, materials::Main.ListContainer)
    wantedLayer = get(Main.persistence, "placements_layer", "entities")
    Main.updateLayerList!(["fgTiles", "bgTiles", "entities", "triggers", "fgDecals", "bgDecals"], row -> row[1] == Main.layerName(targetLayer))

    Main.redrawingFuncs["tools"] = drawSelections
    Main.redrawLayer!(toolsLayer)
end

function layerSelected(list::Main.ListContainer, materials::Main.ListContainer, selected::String)
    global selections = Set{Tuple{String, Main.Rectangle, Any, Number}}()
    global targetLayer = Main.getLayerByName(drawingLayers, selected)
    Main.persistence["placements_layer"] = selected
end

function selectionMotionAbs(rect::Main.Rectangle)
    if rect != selectionRect
        global selectionRect = rect

        Main.redrawLayer!(toolsLayer)
    end
end

function selectionMotionAbs(x1::Number, y1::Number, x2::Number, y2::Number)
    if lastX == -1 || lastY == -1
        ctrl = Main.modifierControl()

        global lastX = ctrl? x1 : div(x1, 8) * 8
        global lastY = ctrl? y1 : div(y1, 8) * 8

        success, target = Main.hasSelectionAt(selections, Main.Rectangle(x1, y1, 1, 1))
        global shouldDrag = success
    end

    if shouldDrag
        if !Main.modifierControl()
            x1 = div(x1, 8) * 8
            y1 = div(y1, 8) * 8

            x2 = div(x2, 8) * 8
            y2 = div(y2, 8) * 8
        end

        dx = x2 - lastX
        dy = y2 - lastY

        global lastX = x2
        global lastY = y2

        if dx != 0 || dy != 0
            for selection in selections
                layer, box, target, node = selection

                if applicable(applyMovement!, target, dx, dy, node)
                    applyMovement!(target, dx, dy, node)
                    notifyMovement!(target)
                end
            end

            Main.redrawLayer!(toolsLayer)
            Main.redrawLayer!(targetLayer)
        end
    end
end

function properlyUpdateSelections!(rect::Main.Rectangle, selections::Set{Tuple{String, Main.Rectangle, Any, Number}})
    retain = Main.modifierShift()

    # Do this before we get new selections
    # This way tiles are settled back into place before we select
    if !retain
        finalizeSelections!(selections)
    end

    unselected, newlySelected = Main.updateSelections!(selections, Main.loadedState.room, Main.layerName(targetLayer), rect, retain=retain)
    initSelections!(newlySelected)
end

function selectionFinishAbs(rect::Main.Rectangle)
    # If we are draging we are techically not making a new selection
    if !shouldDrag
        properlyUpdateSelections!(rect, selections)
    end

    clearDragging!()

    global selectionRect = Main.Rectangle(0, 0, 0, 0)

    Main.redrawLayer!(toolsLayer)
end

function leftClickAbs(x::Number, y::Number)
    rect = Main.Rectangle(x, y, 1, 1)
    properlyUpdateSelections!(rect, selections)

    clearDragging!()

    Main.redrawLayer!(toolsLayer)
end

function layersChanged(layers::Array{Main.Layer, 1})
    wantedLayer = get(Main.persistence, "placements_layer", "entities")

    global drawingLayers = layers
    global toolsLayer = Main.getLayerByName(layers, "tools")
    global targetLayer = Main.selectLayer!(layers, wantedLayer, "entities")
end

function applyTileSelecitonBrush!(target::Main.TileSelection, clear::Bool=false)
    roomTiles = target.fg? Main.loadedState.room.fgTiles : Main.loadedState.room.bgTiles
    tiles = clear? fill('0', size(target.tiles)) : target.tiles

    x, y = floor(Int, target.selection.x / 8), floor(Int, target.selection.y / 8)
    brush = Main.Brush(
        "Selection Finisher",
        clear? fill(1, size(tiles) .- 2) : tiles[2:end - 1, 2:end - 1] .!= '0'
    )

    Main.applyBrush!(brush, roomTiles, tiles[2:end - 1, 2:end - 1], x + 1, y + 1)
end

function finalizeSelections!(targets::Set{Tuple{String, Main.Rectangle, Any, Number}})
    for selection in targets
        layer, box, target, node = selection

        if layer == "fgTiles" || layer == "bgTiles"
            applyTileSelecitonBrush!(target, false)
        end
    end

    if !isempty(targets)
        Main.redrawLayer!(targetLayer)
    end
end

function initSelections!(targets::Set{Tuple{String, Main.Rectangle, Any, Number}})
    for selection in targets
        layer, box, target, node = selection

        if layer == "fgTiles" || layer == "bgTiles"
            applyTileSelecitonBrush!(target, true)
        end
    end

    if !isempty(targets)
        Main.redrawLayer!(targetLayer)
    end
end

function applyMovement!(target::Union{Main.Maple.Entity, Main.Maple.Trigger}, ox::Number, oy::Number, node::Number=0)
    if node == 0
        target.data["x"] += ox
        target.data["y"] += oy

    else
        nodes = get(target.data, "nodes", ())

        if length(nodes) >= node
            nodes[node] = nodes[node] .+ (ox, oy)
        end
    end
end

function applyMovement!(decal::Main.Maple.Decal, ox::Number, oy::Number, node::Number=0)
    decal.x += ox
    decal.y += oy
end

function applyMovement!(target::Main.TileSelection, ox::Number, oy::Number, node::Number=0)
    target.offsetX += ox
    target.offsetY += oy

    target.selection = Main.Rectangle(target.startX + floor(target.offsetX / 8) * 8, target.startY + floor(target.offsetY / 8) * 8, target.selection.w, target.selection.h)
end

function notifyMovement!(entity::Main.Maple.Entity)
    Main.eventToModules(Main.loadedEntities, "moved", entity)
    Main.eventToModules(Main.loadedEntities, "moved", entity, Main.loadedState.room)
end

function notifyMovement!(trigger::Main.Maple.Trigger)
    Main.eventToModules(Main.loadedTriggers, "moved", trigger)
    Main.eventToModules(Main.loadedTriggers, "moved", trigger, Main.loadedState.room)
end

function notifyMovement!(decal::Main.Maple.Decal)
    # Decals doesn't care
end

function notifyMovement!(target::Main.TileSelection)
    # Decals doesn't care
end

resizeModifiers = Dict{Integer, Tuple{Number, Number}}(
    # w, h
    # Decrease / Increase width
    Int('q') => (1, 0),
    Int('w') => (-1, 0),

    # Decrease / Increase height
    Int('a') => (0, 1),
    Int('s') => (0, -1)
)

addNodeKey = Int('n')

moveDirections = Dict{Integer, Tuple{Number, Number}}(
    Main.Gtk.GdkKeySyms.Left => (-1, 0),
    Main.Gtk.GdkKeySyms.Right => (1, 0),
    Main.Gtk.GdkKeySyms.Down => (0, 1),
    Main.Gtk.GdkKeySyms.Up => (0, -1)
)

# Turns out having scales besides -1 and 1 on decals causes weird behaviour?
scaleMultipliers = Dict{Integer, Tuple{Number, Number}}(
    # Vertical Flip
    Int('v') => (1, -1),

    # Horizontal Flip
    Int('h') => (-1, 1),
)

function handleMovement(event::Main.eventKey)
    redraw = false
    step = Main.modifierControl()? 1 : 8

    for selection in selections
        name, box, target, node = selection
        ox, oy = moveDirections[event.keyval] .* step

        if applicable(applyMovement!, target, ox, oy, node)
            applyMovement!(target, ox, oy, node)
            notifyMovement!(target)

            redraw = true
        end
    end

    return redraw
end

function handleResize(event::Main.eventKey)
    redraw = false
    step = Main.modifierControl()? 1 : 8

    for selection in selections
        name, box, target, node = selection
        extraW, extraH = resizeModifiers[event.keyval] .* step

        if (name == "entities" || name == "triggers") && node == 0
            horizontal, vertical = Main.canResize(target)
            minWidth, minHeight = Main.minimumSize(target)

            baseWidth = get(target.data, "width", minWidth)
            baseHeight = get(target.data, "height", minHeight)

            width = horizontal? (max(baseWidth + extraW, minWidth)) : baseWidth
            height = vertical? (max(baseHeight + extraH, minHeight)) : baseHeight

            target.data["width"] = width
            target.data["height"] = height

            redraw = true

        elseif name == "fgDecals" || name == "bgDecals"
            extraW, extraH = resizeModifiers[event.keyval]
            minVal, maxVal = decalScaleVals
            
            # Ready for when decals render correctly
            #target.scaleX = sign(target.scaleX) * clamp(abs(target.scaleX) * 2.0^extraW, minVal, maxVal)
            #target.scaleY = sign(target.scaleY) * clamp(abs(target.scaleY) * 2.0^extraH, minVal, maxVal)

            redraw = true
        end
    end

    return redraw
end

function handleScaling(event::Main.eventKey)
    redraw = false

    for selection in selections
        name, box, target, node = selection
        msx, msy = scaleMultipliers[event.keyval]

        if isa(target, Main.Maple.Decal)
            target.scaleX *= msx
            target.scaleY *= msy

            redraw = true
        end
    end

    return redraw
end

function handleAddNodes(event::Main.eventKey)
    redraw = false

    for selection in selections
        name, box, target, node = selection

        if name == "entities"
            least, most = Main.nodeLimits(target)
            nodes = get(target.data, "nodes", [])

            if most == -1 || length(nodes) + 1 <= most
                x, y = target.data["x"], target.data["y"]

                if node > 0
                    x, y = nodes[node]
                end

                insert!(nodes, node + 1, (x + 16, y))
                redraw = true

                target.data["nodes"] = nodes
            end
        end
    end

    return redraw
end

function handleDeletion(selections::Set{Tuple{String, Main.Rectangle, Any, Number}})
    res = !isempty(selections)
    targetName = Main.layerName(targetLayer)

    if haskey(Main.selectionTargets, targetName)
        targetList = Main.selectionTargets[targetName](Main.loadedState.room)

        # Sort entities, otherwise deletion will break
        processedSelections = targetName == "entities"? sort(collect(selections), by=r -> (r[3].id, r[4]), rev=true) : selections
        for selection in processedSelections
            name, box, target, node = selection

            index = findfirst(targetList, target)
            if index != 0
                if node == 0
                    deleteat!(targetList, index)

                elseif name == "entities"
                    least, most = Main.nodeLimits(target)
                    nodes = get(target.data, "nodes", [])

                    # Delete the node if that doesn't result in too few nodes
                    # Delete the whole entity if it does
                    if length(nodes) - 1 >= least && length(nodes) >= node
                        deleteat!(nodes, node)

                    else
                        deleteat!(targetList, index)
                    end
                end
            end
        end

    elseif targetName == "fgTiles" || targetName == "bgTiles"
        # Don't need to do anything, the tiles are already removed from the map
    end

    empty!(selections)

    return res
end

# Refactor and prettify code once we know how to handle tiles here,
# this also includes the handle functions
function keyboard(event::Main.eventKey)
    needsRedraw = false

    if haskey(moveDirections, event.keyval)
        needsRedraw |= handleMovement(event)
    end

    if haskey(resizeModifiers, event.keyval)
        needsRedraw |= handleResize(event)
    end

    if haskey(scaleMultipliers, event.keyval)
        needsRedraw |= handleScaling(event)
    end

    if event.keyval == addNodeKey
        needsRedraw |= handleAddNodes(event)
    end

    if event.keyval == Main.Gtk.GdkKeySyms.Delete
        needsRedraw |= handleDeletion(selections)
    end

    if needsRedraw
        Main.redrawLayer!(toolsLayer)
        Main.redrawLayer!(targetLayer)
    end

    return true
end

end