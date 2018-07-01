mutable struct TileSelection
    fg::Bool
    tiles::Array{Char, 2}
    selection::Rectangle
    startX::Number
    startY::Number
    offsetX::Number
    offsetY::Number
end

TileSelection(fg::Bool, tiles::Array{Char, 2}, selection::Rectangle) = TileSelection(fg, tiles, selection, selection.x, selection.y, 0, 0)

selectionTargets = Dict{String, Function}(
    "entities" => room -> room.entities,
    "triggers" => room -> room.triggers,
    "bgDecals" => room -> room.bgDecals,
    "fgDecals" => room -> room.fgDecals
)

function getSelection(trigger::Maple.Trigger, node::Number=0)
    x, y = Int(trigger.data["x"]), Int(trigger.data["y"])
    width, height = Int(trigger.data["width"]), Int(trigger.data["height"])

    return true, Rectangle(x, y, width, height)
end

function getSelection(decal::Maple.Decal, node::Number=0)
    return true, decalSelection(decal)
end

function getSelection(entity::Maple.Entity, node::Number=0)
    selectionRes = eventToModules(loadedEntities, "selection", entity) 

    if isa(selectionRes, Tuple)
        success, rect = selectionRes

        if success
            return true, rect
        end
    end

    return false, false
end

function getSelection(target::TileSelection, node::Number=0)
    return true, target.selection
end

# TODO - Use mouse position and check if its closer to the center as well
# Area is "good enough" for now
function bestSelection(set::Set{Tuple{String, Rectangle, Any, Number}})
    best = nothing
    bestVal = typemax(Int)

    for selection in set
        layer, rect, target, node = selection
        area = rect.w * rect.h

        if area < bestVal
            best = selection
            bestVal = area
        end
    end

    return best
end

function getSelected(room::Room, name::String, selection::Rectangle)
    res = Set{Tuple{String, Rectangle, Any, Number}}()

    # Rectangular based selection - Triggers, Entities, Decals
    if haskey(selectionTargets, name)
        targets = selectionTargets[name](room)

        for target in targets
            success, rect = getSelection(target)

            if success
                if isa(rect, Rectangle)
                    if checkCollision(selection, rect)
                        push!(res, (name, rect, target, 0))
                    end

                elseif isa(rect, Array{Rectangle, 1})
                    for (i, r) in enumerate(rect)
                        if checkCollision(selection, r)
                            # The first rect is the main entity itself, followed by the nodes
                            push!(res, (name, r, target, i - 1))
                        end
                    end
                end
            end
        end

    # Tile based selections
    elseif name == "fgTiles" || name == "bgTiles"
        fg = name == "fgTiles"
        tiles = fg? room.fgTiles.data : room.bgTiles.data

        tx, ty = floor(Int, selection.x / 8), floor(Int, selection.y / 8)
        tw, th = ceil(Int, selection.w / 8), ceil(Int, selection.h / 8) 

        gx, gy = tx * 8, ty * 8
        gw, gh = tw * 8, th * 8
        gridSelection = Rectangle(gx, gy, gw, gh)

        drawingTiles = fill('0', (th + 2, tw + 2))
        drawingTiles[2:end - 1, 2:end - 1] = get(tiles, (ty + 1:ty + th, tx + 1:tx + tw), '0')

        target = TileSelection(
            fg,
            drawingTiles,
            gridSelection
        )

        push!(res, (name, gridSelection, target, 0))
    end

    return res
end

getSelected(room::Room, layer::Layer, selection::Rectangle) = getSelected(room, layerName(layer), selection)

function hasSelectionAt(selections::Set{Tuple{String, Rectangle, Any, Number}}, rect::Rectangle)
    for selection in selections
        layer, box, target, node = selection

        success, targetRect = getSelection(target)
        if isa(targetRect, Rectangle) && checkCollision(rect, targetRect) && node == 0
            return true, target

        elseif isa(targetRect, Array{Rectangle, 1})
            for (i, r) in enumerate(targetRect)
                if checkCollision(rect, r) && node == i - 1
                    return true, target
                end
            end
        end
    end

    return false, false
end

function updateSelections!(selections::Set{Tuple{String, Rectangle, Any, Number}}, room::Room, name::String, rect::Rectangle; retain::Bool=false, best::Bool=false)
    # Return selections that are no longer selected
    unselected = Set{Tuple{String, Rectangle, Any, Number}}()
    newlySelected = Set{Tuple{String, Rectangle, Any, Number}}()

    # Holding shift keeps the last selection as well
    if !retain
        unselected = deepcopy(selections)
        empty!(selections)
    end

    # Make sure the new selections are unique
    validSelections = getSelected(room, name, rect)
    if best
        target = bestSelection(validSelections)
        if target !== nothing
            push!(selections, target)
            push!(newlySelected, target)
        end

    else
        union!(selections, validSelections)
        union!(newlySelected, validSelections)
    end

    return unselected, newlySelected
end

updateSelections!(selections::Set{Tuple{String, Rectangle, Any, Number}}, room::Room, layer::Layer, rect::Rectangle) = updateSelections!(selections, room, layerName(layer), rect)