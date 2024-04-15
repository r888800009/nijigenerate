/*
    Copyright © 2020-2023, Inochi2D Project
    Distributed under the 2-Clause BSD License, see LICENSE file.
    
    Authors: Luna Nielsen
*/
module creator.actions.node;
import creator.core.actionstack;
import creator.actions;
import creator;
import inochi2d;
import std.format;
import i18n;
import std.exception;
import std.array: insertInPlace;
import std.algorithm.mutation: remove;
import std.algorithm.searching;

/**
    An action that happens when a node is changed
*/
class NodeMoveAction : Action {
public:

    /**
        Descriptive name
    */
    string descrName;
    
    /**
        Which index in to the parent the nodes should be placed
    */
    size_t parentOffset;

    /**
        Previous parent of node
    */
    Node[uint] prevParents;
    size_t[uint] prevOffsets;

    /**
        Nodes that was moved
    */
    Node[] nodes;

    /**
        New parent of node
    */
    Node newParent;

    /**
        The original transform of the node
    */
    Transform[uint] originalTransform;

    /**
        The new transform of the node
    */
    Transform[uint] newTransform;

    /**
        Creates a new node change action
    */
    this(Node[] nodes, Node new_, size_t pOffset = 0) {
        this.newParent = new_;
        this.nodes = nodes;
        this.parentOffset = pOffset;

        // Enforce reparenting rules
        foreach(sn; nodes) enforce(sn.canReparent(new_), _("%s can not be reparented in to %s due to a circular dependency.").format(sn.name, new_.name));
        
        // Reparent
        foreach(ref sn; nodes) {
            
            // Store ref to prev parent
            if (sn.parent) {
                originalTransform[sn.uuid] = sn.localTransform;
                prevParents[sn.uuid] = sn.parent;
                prevOffsets[sn.uuid] = sn.getIndexInParent();
            }

            // Set relative position
            if (new_) {
                sn.reparent(new_, pOffset);
                sn.transformChanged();
                sn.notifyChange(sn);
            } else sn.parent = null;
            if (sn.uuid in prevParents && prevParents[sn.uuid]) prevParents[sn.uuid].notifyChange(sn);
            newTransform[sn.uuid] = sn.localTransform;
        }
        incActivePuppet().rescanNodes();
    
        // Set visual name
        if (nodes.length == 1) descrName = nodes[0].name;
        else descrName = _("nodes");
    }

    /**
        Rollback
    */
    void rollback() {
        foreach(ref sn; nodes) {
            if (sn.uuid in prevParents && prevParents[sn.uuid]) {
                if (!sn.lockToRoot()) sn.setRelativeTo(prevParents[sn.uuid]);
                sn.reparent(prevParents[sn.uuid], prevOffsets[sn.uuid]);
                sn.localTransform = originalTransform[sn.uuid];
                sn.transformChanged();
                if (newParent) newParent.notifyChange(sn);
                sn.notifyChange(sn);
            } else sn.parent = null;
        }
        incActivePuppet().rescanNodes();
    }

    /**
        Redo
    */
    void redo() {
        foreach(sn; nodes) {
            if (newParent) {
                if (!sn.lockToRoot()) sn.setRelativeTo(newParent);
                sn.reparent(newParent, parentOffset);
                sn.localTransform = newTransform[sn.uuid];
                sn.transformChanged();
                if (sn.uuid in prevParents && prevParents[sn.uuid]) prevParents[sn.uuid].notifyChange(sn);
                sn.notifyChange(sn);
            } else sn.parent = null;
        }
        incActivePuppet().rescanNodes();
    }

    /**
        Describe the action
    */
    string describe() {
        if (prevParents.length == 0) return _("Created %s").format(descrName);
        if (newParent is null) return _("Deleted %s").format(descrName);
        return _("Moved %s to %s").format(descrName, newParent.name);
    }

    /**
        Describe the action
    */
    string describeUndo() {
        if (prevParents.length == 0) return _("Created %s").format(descrName);
        if (nodes.length == 1 && prevParents.length == 1 && prevParents.values[0]) return  _("Moved %s from %s").format(descrName, prevParents[nodes[0].uuid].name);
        return _("Moved %s from origin").format(descrName);
    }

    /**
        Gets name of this action
    */
    string getName() {
        return this.stringof;
    }
    
    bool merge(Action other) { return false; }
    bool canMerge(Action other) { return false; }
}

/**
    An action that happens when a node is replaced
*/
class NodeReplaceAction : Action {
public:

    /**
        Descriptive name
    */
    string descrName;
    
    /**
        Nodes that was moved
    */
    Node srcNode;
    Node toNode;
    Node[] children;
    bool deepCopy;

    /**
        Creates a new node change action
    */
    this(Node src, Node to, bool deepCopy) {
        srcNode = src;
        toNode = to;

        if (src.parent !is null)
            children = src.children.dup;
        else if (to.parent !is null)
            children = to.children.dup;

        if (cast(DynamicComposite)srcNode !is null && 
            cast(DynamicComposite)toNode is null &&
            cast(Part)toNode !is null) {
            deepCopy = false;
        }
        this.deepCopy = deepCopy;

        // Set visual name
        descrName = src.name;

        if (toNode.parent is null)
            redo();
    }

    /**
        Rollback
    */
    void rollback() {
        auto parent = toNode.parent;
        assert(parent !is null);
        ulong pOffset = parent.children.countUntil(toNode);
        toNode.reparent(null, 0);
        srcNode.reparent(parent, pOffset);
        if (deepCopy) {
            foreach (i, child; children) {
                child.reparent(srcNode, i);
                child.notifyChange(child);
            }
        }
    }

    /**
        Redo
    */
    void redo() {
        auto parent = srcNode.parent;
        assert(parent !is null);
        ulong pOffset = parent.children.countUntil(srcNode);
        srcNode.reparent(null, 0);
        toNode.reparent(parent, pOffset);
        if (deepCopy) {
            foreach (i, child; children) {
                child.reparent(toNode, i);
                child.notifyChange(child);
            }
        }
    }

    /**
        Describe the action
    */
    string describe() {
        return _("Change type of %s to %s").format(descrName, toNode.typeId);
    }

    /**
        Describe the action
    */
    string describeUndo() {
        return _("Revert type of %s to %s").format(descrName, srcNode.typeId);
    }

    /**
        Gets name of this action
    */
    string getName() {
        return this.stringof;
    }
    
    bool merge(Action other) { return false; }
    bool canMerge(Action other) { return false; }
}

/**
    An action that happens when a node is changed
*/
class PartAddRemoveMaskAction(bool addAction = false) : Action {
public:

    /**
        Previous parent of node
    */
    Part target;
    MaskingMode mode;
    size_t offset;
    Drawable maskSrc;

    /**
        Creates a new node change action
    */
    this(Drawable drawable, Part target, MaskingMode mode) {
        this.maskSrc = drawable;
        this.target = target;

        if (addAction) {
            offset = target.masks.length;
            target.masks ~= MaskBinding(maskSrc.uuid, mode, drawable);

        } else {
            foreach (i, masker; target.masks) {
                if (masker.maskSrc == maskSrc) {
                    offset = i;
                    target.masks = target.masks.remove(i);
                    break;
                }
            }
        }
        target.notifyChange(target);
        incActivePuppet().rescanNodes();
    }

    /**
        Rollback
    */
    void rollback() {
        if (addAction) {
            target.notifyChange(target);
            target.masks = target.masks.remove(offset);
        } else {
            target.masks.insertInPlace(offset, MaskBinding(maskSrc.uuid, mode, maskSrc));
            target.notifyChange(target);
        }
        incActivePuppet().rescanNodes();
    }

    /**
        Redo
    */
    void redo() {
        if (addAction) {
            target.masks.insertInPlace(offset, MaskBinding(maskSrc.uuid, mode, maskSrc));
            target.notifyChange(target);
        } else {
            target.notifyChange(target);
            target.masks = target.masks.remove(offset);
        }
        incActivePuppet().rescanNodes();
    }

    /**
        Describe the action
    */
    string describe() {
        if (addAction) return _("%s is added to mask of %s").format(maskSrc.name, target.name);
        else return _("%s is deleted from mask of %s").format(maskSrc.name, target.name);
    }

    /**
        Describe the action
    */
    string describeUndo() {
        if (addAction) return _("%s is deleted from mask of %s").format(maskSrc.name, target.name);
        else return _("%s is added to mask of %s").format(maskSrc.name, target.name);
    }

    /**
        Gets name of this action
    */
    string getName() {
        return this.stringof;
    }
    
    bool merge(Action other) { return false; }
    bool canMerge(Action other) { return false; }
}

alias PartAddMaskAction = PartAddRemoveMaskAction!true;
alias PartRemoveMaskAction = PartAddRemoveMaskAction!false;
/**
    An action that happens when a node is changed
*/
class DrawableAddRemoveWeldingAction(bool addAction = false) : Action {
public:

    /**
        Previous parent of node
    */
    Drawable drawable;
    size_t offset;
    Drawable target;
    ptrdiff_t[] weldedVertexIndices;
    float weight;

    /**
        Creates a new node change action
    */
    this(Drawable drawable, Drawable target, ptrdiff_t[] weldedVertexIndices, float weight) {
        this.drawable = drawable;
        this.target = target;

        if (addAction) {
            offset = drawable.welded.length;
            drawable.addWeldedTarget(target, weldedVertexIndices, weight);

        } else {
            drawable.removeWeldedTarget(target);
        }
        incActivePuppet().rescanNodes();
    }

    /**
        Rollback
    */
    void rollback() {
        if (addAction) {
            drawable.removeWeldedTarget(target);
        } else {
            drawable.addWeldedTarget(target, weldedVertexIndices, weight);
        }
        incActivePuppet().rescanNodes();
    }

    /**
        Redo
    */
    void redo() {
        if (addAction) {
            drawable.addWeldedTarget(target, weldedVertexIndices, weight);
        } else {
            drawable.removeWeldedTarget(target);
        }
        incActivePuppet().rescanNodes();
    }

    /**
        Describe the action
    */
    string describe() {
        if (addAction) return _("%s is added to welded targets of %s").format(target.name, drawable.name);
        else return _("%s is deleted from welded targets of %s").format(target.name, drawable.name);
    }

    /**
        Describe the action
    */
    string describeUndo() {
        if (addAction) return _("%s is deleted from welded targets of %s").format(target.name, drawable.name);
        else return _("%s is added to welded targets of %s").format(target.name, drawable.name);
    }

    /**
        Gets name of this action
    */
    string getName() {
        return this.stringof;
    }
    
    bool merge(Action other) { return false; }
    bool canMerge(Action other) { return false; }
}

alias DrawableAddWeldingAction = DrawableAddRemoveWeldingAction!true;
alias DrawableRemoveWeldingAction = DrawableAddRemoveWeldingAction!false;

/**
    Action for whether a node was activated or deactivated
*/
class NodeActiveAction : Action {
public:
    Node self;
    bool newState;

    /**
        Rollback
    */
    void rollback() {
        self.setEnabled(!newState);
    }

    /**
        Redo
    */
    void redo() {
        self.setEnabled(newState);
    }

    /**
        Describe the action
    */
    string describe() {
        return "%s %s".format(newState ? _("Enabled") : _("Disabled"), self.name);
    }

    /**
        Describe the action
    */
    string describeUndo() {
        return _("%s was %s").format(self.name, !newState ? _("Enabled") : _("Disabled"));
    }

    /**
        Gets name of this action
    */
    string getName() {
        return this.stringof;
    }
    
    bool merge(Action other) { return false; }
    bool canMerge(Action other) { return false; }
}

/**
    Moves multiple children with history
*/
void incMoveChildrenWithHistory(Node[] n, Node to, size_t offset) {
    // Push action to stack
    incActionPush(new NodeMoveAction(
        n,
        to,
        offset
    ));
}

/**
    Moves child with history
*/
void incMoveChildWithHistory(Node n, Node to, size_t offset) {
    incMoveChildrenWithHistory([n], to, offset);
}

/**
    Adds child with history
*/
void incAddChildWithHistory(Node n, Node to, string name=null) {
    if (to is null) to = incActivePuppet().root;

    // Push action to stack
    incActionPush(new NodeMoveAction(
        [n],
        to
    ));

    n.insertInto(to, Node.OFFSET_START);
    n.localTransform.clear();
    if (name is null) n.name = _("Unnamed ")~_(n.typeId());
    else n.name = name;
    incActivePuppet().rescanNodes();
}

GroupAction incDeleteMaskOfNode(Node n, GroupAction group = null) {
    auto removedDrawables = incActivePuppet().findNodesType!Drawable(n);
    auto parts = incActivePuppet().findNodesType!Part(incActivePuppet().root);
    foreach (drawable; removedDrawables) {
        foreach (target; parts) {
            auto idx = target.getMaskIdx(drawable);
            if (idx >= 0) {
                if (group is null)
                    group = new GroupAction();
                group.addAction(new PartRemoveMaskAction(drawable, target, target.masks[idx].mode));
            }
        }
    }
    return group;
}

/**
    Deletes child with history
*/
void incDeleteChildWithHistory(Node n) {
    auto group = incDeleteMaskOfNode(n);
    if (group !is null) {
        group.addAction(new NodeMoveAction(
            [n],
            null
        ));
        incActionPush(group);
    } else {
        // Push action to stack
        incActionPush(new NodeMoveAction(
            [n],
            null
        ));
    }
    
    incActivePuppet().rescanNodes();
}

/**
    Deletes child with history
*/
void incDeleteChildrenWithHistory(Node[] ns) {
    GroupAction group = null;
    foreach (n; ns) {
        incDeleteMaskOfNode(n, group);
    }
    if (group !is null) {
        // Push action to stack
        group.addAction(new NodeMoveAction(
            ns,
            null
        ));
        incActionPush(group);
    } else {
        // Push action to stack
        incActionPush(new NodeMoveAction(
            ns,
            null
        ));
    }

    incActivePuppet().rescanNodes();
}

/**
    Node value changed action
*/
class NodeValueChangeAction(TNode, T) : Action if (is(TNode : Node)) {
public:
    alias TSelf = typeof(this);
    TNode node;
    T oldValue;
    T newValue;
    T* valuePtr;
    string name;

    this(string name, TNode node, T oldValue, T newValue, T* valuePtr) {
        this.name = name;
        this.node = node;
        this.oldValue = oldValue;
        this.newValue = newValue;
        this.valuePtr = valuePtr;
        node.notifyChange(node);
    }

    /**
        Rollback
    */
    void rollback() {
        *valuePtr = oldValue;
        node.notifyChange(node);
    }

    /**
        Redo
    */
    void redo() {
        *valuePtr = newValue;
        node.notifyChange(node);
    }

    /**
        Describe the action
    */
    string describe() {
        return _("%s->%s changed to %s").format(node.name, name, newValue);
    }

    /**
        Describe the action
    */
    string describeUndo() {
        return _("%s->%s changed from %s").format(node.name, name, oldValue);
    }

    /**
        Gets name of this action
    */
    string getName() {
        return name;
    }
    
    /**
        Merge
    */
    bool merge(Action other) {
        if (this.canMerge(other)) {
            this.newValue = (cast(TSelf)other).newValue;
            return true;
        }
        return false;
    }

    /**
        Gets whether this node can merge with an other
    */
    bool canMerge(Action other) {
        TSelf otherChange = cast(TSelf) other;
        return (otherChange !is null && otherChange.getName() == this.getName());
    }
}

class NodeRootBaseSetAction : Action {
public:
    alias TSelf = typeof(this);
    Node node;
    bool origState;
    bool state;


    this(Node n, bool state) {
        this.node = n;
        this.origState = n.lockToRoot;
        this.state = state;

        n.lockToRoot = this.state;
    }

    /**
        Rollback
    */
    void rollback() {
        this.node.lockToRoot = origState;
        node.notifyChange(node);
    }

    /**
        Redo
    */
    void redo() {
        this.node.lockToRoot = state;
        node.notifyChange(node);
    }

    /**
        Describe the action
    */
    string describe() {
        if (origState) return _("%s locked to root node").format(node.name);
        else return _("%s unlocked from root node").format(node.name);
    }

    /**
        Describe the action
    */
    string describeUndo() {
        if (state) return _("%s locked to root node").format(node.name);
        else return _("%s unlocked from root node").format(node.name);
    }

    /**
        Gets name of this action
    */
    string getName() {
        return this.stringof;
    }
    
    /**
        Merge
    */
    bool merge(Action other) {
        if (this.canMerge(other)) {
            this.node.lockToRoot = !state;
            this.state = !state;
            return true;
        }
        return false;
    }

    /**
        Gets whether this node can merge with an other
    */
    bool canMerge(Action other) {
        TSelf otherChange = cast(TSelf) other;
        return otherChange && otherChange.node == this.node;
    }
}

/**
    Locks to root node
*/
void incLockToRootNode(Node n) {
    // Push action to stack
    incActionPush(new NodeRootBaseSetAction(
        n, 
        !n.lockToRoot
    ));
}