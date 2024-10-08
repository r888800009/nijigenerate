module nijigenerate.viewport.common.mesheditor.brushes.base;
import inmath;

interface Brush {
    string name();
    bool isInside(vec2 center, vec2 pos);
    float weightAt(vec2 center, vec2 pos);
    float[] weightsAt(vec2 center, vec2[] positions);
    void draw(vec2 center, mat4 transform);
    bool configure();
}
