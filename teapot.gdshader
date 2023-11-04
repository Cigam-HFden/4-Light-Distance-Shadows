shader_type spatial;
uniform float seed_variation = 0.0;
varying float elapsed_time;
varying vec3 world_camera;
varying vec3 world_position;
const int MAX_STEPS = 100;
const float MAX_DIST = 100.0;
const float SURF_DIST = 1e-3;
float rand(vec2 x) {
    return fract(cos(mod(dot(x, vec2(13.9898, 8.141)), 3.14)) * 43758.5453);
}
vec2 rand2(vec2 x) {
    return fract(cos(mod(vec2(dot(x, vec2(13.9898, 8.141)),
						      dot(x, vec2(3.4562, 17.398))), vec2(3.14))) * 43758.5453);
}
vec3 rand3(vec2 x) {
    return fract(cos(mod(vec3(dot(x, vec2(13.9898, 8.141)),
							  dot(x, vec2(3.4562, 17.398)),
                              dot(x, vec2(13.254, 5.867))), vec3(3.14))) * 43758.5453);
}
float param_rnd(float minimum, float maximum, float seed) {
	return minimum+(maximum-minimum)*rand(vec2(seed));
}
vec3 rgb2hsv(vec3 c) {
	vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = c.g < c.b ? vec4(c.bg, K.wz) : vec4(c.gb, K.xy);
	vec4 q = c.r < p.x ? vec4(p.xyw, c.r) : vec4(c.r, p.yzx);
	float d = q.x - min(q.w, q.y);
	float e = 1.0e-10;
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}
vec3 hsv2rgb(vec3 c) {
	vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
	vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
	return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}
float cross2( in vec2 a, in vec2 b ) { return a.x*b.y - a.y*b.x; }
float sdBezier( in vec2 pos, in vec2 A, in vec2 B, in vec2 C ) {	
	vec2 a = B - A;
	vec2 b = A - 2.0*B + C;
	vec2 c = a * 2.0;
	vec2 d = A - pos;
	float kk = 1.0/dot(b,b);
	float kx = kk * dot(a,b);
	float ky = kk * (2.0*dot(a,a)+dot(d,b))/3.0;
	float kz = kk * dot(d,a);	  
	float res = 0.0;
	float sgn = 0.0;
	float p = ky - kx*kx;
	float p3 = p*p*p;
	float q = kx*(2.0*kx*kx - 3.0*ky) + kz;
	float h = q*q + 4.0*p3;
	float rvx;
	if( h>=0.0 ) { // 1 root
		h = sqrt(h);
		vec2 x = (vec2(h,-h)-q)/2.0;
		
		if( abs(p)<0.001 )
        {
            float k = p3/q;              // linear approx
			//float k = (1.0-p3/q2)*p3/q;  // quadratic approx 
            x = vec2(k,-k-q);  
        }
		
		vec2 uv = sign(x)*pow(abs(x), vec2(1.0/3.0));
		rvx = uv.x+uv.y-kx;
		float t = clamp(rvx, 0.0, 1.0);
		vec2 q2 = d+(c+b*t)*t;
		res = dot(q2, q2);
		sgn = cross2(c+2.0*b*t, q2);
	} else {   // 3 roots
		float z = sqrt(-p);
		float v = acos(q/(p*z*2.0))/3.0;
		float m = cos(v);
		float n = sin(v)*1.732050808;
		vec3  t = clamp(vec3(m+m,-n-m,n-m)*z-kx, 0.0, 1.0);
		vec2  qx=d+(c+b*t.x)*t.x; float dx=dot(qx, qx), sx = cross2(c+2.0*b*t.x,qx);
		vec2  qy=d+(c+b*t.y)*t.y; float dy=dot(qy, qy), sy = cross2(c+2.0*b*t.y,qy);
		if( dx<dy ) { res=dx; sgn=sx; rvx = t.x; } else { res=dy; sgn=sy; rvx = t.y; }
	}
	
	return sqrt(res);
}
float sdCylinder(vec3 p, float h, float r) {
	vec2 d = abs(vec2(length(p.xz), p.y)) - vec2(r, h);
	return min(max(d.x, d.y),0.0) + length(max(d, 0.0));
}
vec2 sdf3d_smooth_union(vec2 d1, vec2 d2, float k) {
	float h = clamp(0.5+0.5*(d2.x-d1.x)/k, 0.0, 1.0);
	return vec2(mix(d2.x, d1.x, h)-k*h*(1.0-h), mix(d2.y, d1.y, step(d1.x, d2.x)));
}
vec2 sdf3d_smooth_subtraction(vec2 d1, vec2 d2, float k ) {
	float h = clamp(0.5-0.5*(d2.x+d1.x)/k, 0.0, 1.0);
	return vec2(mix(d2.x, -d1.x, h )+k*h*(1.0-h), d2.y);
}
vec2 sdf3d_smooth_intersection(vec2 d1, vec2 d2, float k ) {
	float h = clamp(0.5-0.5*(d2.x-d1.x)/k, 0.0, 1.0);
	return vec2(mix(d2.x, d1.x, h)+k*h*(1.0-h), mix(d1.y, d2.y, step(d1.x, d2.x)));
}
vec2 sdf3dc_union(vec2 a, vec2 b) {
	return vec2(min(a.x, b.x), mix(b.y, a.y, step(a.x, b.x)));
}
vec2 sdf3dc_sub(vec2 a, vec2 b) {
	return vec2(max(-a.x, b.x), a.y);
}
vec2 sdf3dc_inter(vec2 a, vec2 b) {
	return vec2(max(a.x, b.x), mix(a.y, b.y, step(a.x, b.x)));
}
vec3 rotate3d(vec3 p, vec3 a) {
	vec3 rv;
	float c;
	float s;
	c = cos(a.x);
	s = sin(a.x);
	rv.x = p.x;
	rv.y = p.y*c+p.z*s;
	rv.z = -p.y*s+p.z*c;
	c = cos(a.y);
	s = sin(a.y);
	p.x = rv.x*c+rv.z*s;
	p.y = rv.y;
	p.z = -rv.x*s+rv.z*c;
	c = cos(a.z);
	s = sin(a.z);
	rv.x = p.x*c+p.y*s;
	rv.y = -p.x*s+p.y*c;
	rv.z = p.z;
	return rv;
}
uniform sampler2D texture_1;
const float texture_1_size = 1024.0;
vec2 scale(vec2 uv, vec2 center, vec2 scale) {
	uv -= center;
	uv /= scale;
	uv += center;
	return uv;
}
vec3 blend3d_normal(vec3 c1, vec3 c2, float opacity) {
	return opacity*c1 + (1.0-opacity)*c2;
}
vec3 blend3d_multiply(vec3 c1, vec3 c2, float opacity) {
	return opacity*c1*c2 + (1.0-opacity)*c2;
}
vec3 blend3d_screen(vec3 c1, vec3 c2, float opacity) {
	return opacity*(1.0-(1.0-c1)*(1.0-c2)) + (1.0-opacity)*c2;
}
float blend3d_overlay_f(float c1, float c2) {
	return (c1 < 0.5) ? (2.0*c1*c2) : (1.0-2.0*(1.0-c1)*(1.0-c2));
}
vec3 blend3d_overlay(vec3 c1, vec3 c2, float opacity) {
	return opacity*vec3(blend3d_overlay_f(c1.x, c2.x), blend3d_overlay_f(c1.y, c2.y), blend3d_overlay_f(c1.z, c2.z)) + (1.0-opacity)*c2;
}
vec3 blend3d_hard_light(vec3 c1, vec3 c2, float opacity) {
	return opacity*0.5*(c1*c2+blend3d_overlay(c1, c2, 1.0)) + (1.0-opacity)*c2;
}
float blend3d_soft_light_f(float c1, float c2) {
	return (c2 < 0.5) ? (2.0*c1*c2+c1*c1*(1.0-2.0*c2)) : 2.0*c1*(1.0-c2)+sqrt(c1)*(2.0*c2-1.0);
}
vec3 blend3d_soft_light(vec3 c1, vec3 c2, float opacity) {
	return opacity*vec3(blend3d_soft_light_f(c1.x, c2.x), blend3d_soft_light_f(c1.y, c2.y), blend3d_soft_light_f(c1.z, c2.z)) + (1.0-opacity)*c2;
}
float blend3d_burn_f(float c1, float c2) {
	return (c1==0.0)?c1:max((1.0-((1.0-c2)/c1)),0.0);
}
vec3 blend3d_burn(vec3 c1, vec3 c2, float opacity) {
	return opacity*vec3(blend3d_burn_f(c1.x, c2.x), blend3d_burn_f(c1.y, c2.y), blend3d_burn_f(c1.z, c2.z)) + (1.0-opacity)*c2;
}
float blend3d_dodge_f(float c1, float c2) {
	return (c1==1.0)?c1:min(c2/(1.0-c1),1.0);
}
vec3 blend3d_dodge(vec3 c1, vec3 c2, float opacity) {
	return opacity*vec3(blend3d_dodge_f(c1.x, c2.x), blend3d_dodge_f(c1.y, c2.y), blend3d_dodge_f(c1.z, c2.z)) + (1.0-opacity)*c2;
}
vec3 blend3d_lighten(vec3 c1, vec3 c2, float opacity) {
	return opacity*max(c1, c2) + (1.0-opacity)*c2;
}
vec3 blend3d_darken(vec3 c1, vec3 c2, float opacity) {
	return opacity*min(c1, c2) + (1.0-opacity)*c2;
}
vec3 blend3d_difference(vec3 c1, vec3 c2, float opacity) {
	return opacity*clamp(c2-c1, vec3(0.0), vec3(1.0)) + (1.0-opacity)*c2;
}
vec3 tex3d_rotate(vec3 p, vec3 a) {
	vec3 rv;
	float c;
	float s;
	c = cos(a.x);
	s = sin(a.x);
	rv.x = p.x;
	rv.y = p.y*c+p.z*s;
	rv.z = -p.y*s+p.z*c;
	c = cos(a.y);
	s = sin(a.y);
	p.x = rv.x*c+rv.z*s;
	p.y = rv.y;
	p.z = -rv.x*s+rv.z*c;
	c = cos(a.z);
	s = sin(a.z);
	rv.x = p.x*c+p.y*s;
	rv.y = -p.x*s+p.y*c;
	rv.z = p.z;
	return rv;
}
const float p_o102763_ax = 35.000000000;
const float p_o102763_ay = 180.000000000;
const float p_o102763_az = 215.000000000;
const float p_o102766_s = 1.400000000;
const float p_o102646_k = 0.021000000;
const float p_o102643_k = 0.039500000;
const float p_o102641_k = 0.000000000;
const float p_o102635_k = 0.025600000;
const float p_o102631_d = 0.083700000;
const float p_o102753_ax = -0.117000000;
const float p_o102753_ay = 0.276000000;
const float p_o102753_bx = 0.567000000;
const float p_o102753_by = 0.354000000;
const float p_o102753_cx = 0.207000000;
const float p_o102753_cy = -0.258000000;
const float p_o102753_r = 0.005000000;
const float p_o102634_r = 0.012000000;
const float p_o102633_x = 0.000000000;
const float p_o102633_y = 0.000000000;
const float p_o102633_z = 0.254700000;
const float p_o102632_l = 0.033400000;
const float p_o102632_r = 0.294300000;
const float p_o102637_d = 0.092700000;
const float p_o102754_ax = -0.033333000;
const float p_o102754_ay = -0.410526000;
const float p_o102754_bx = -0.124561000;
const float p_o102754_by = -0.273684000;
const float p_o102754_cx = 0.173069000;
const float p_o102754_cy = -0.260635000;
const float p_o102754_r = 0.014000000;
const float p_o102640_x = 0.000000000;
const float p_o102640_y = 0.000000000;
const float p_o102640_z = -0.413800000;
const float p_o102639_s = 1.000000000;
const float p_o102639_sx = 1.000000000;
const float p_o102639_sy = 1.000000000;
const float p_o102639_sz = 0.589990000;
const float p_o102638_r = 0.053400000;
const float p_o102644_x = 0.369700000;
const float p_o102644_y = 0.000000000;
const float p_o102644_z = 0.000000000;
const float p_o102645_r = 0.016300000;
const float p_o102642_d = 0.035400000;
const float p_o102760_ax = 0.233000000;
const float p_o102760_ay = -0.078000000;
const float p_o102760_bx = 0.240000000;
const float p_o102760_by = -0.229000000;
const float p_o102760_cx = -0.045000000;
const float p_o102760_cy = -0.193000000;
const float p_o102760_r = 0.006000000;
const float p_o102762_ax = -0.037705000;
const float p_o102762_ay = 0.186885000;
const float p_o102762_bx = 0.227869000;
const float p_o102762_by = 0.113000000;
const float p_o102762_cx = 0.233000000;
const float p_o102762_cy = -0.080000000;
const float p_o102762_r = 0.006000000;
const float p_o102647_x = -0.555200000;
const float p_o102647_y = 0.000000000;
const float p_o102647_z = 0.000000000;
const float p_o102670_x = 0.000000000;
const float p_o102670_y = 0.006400000;
const float p_o102670_z = 0.000000000;
const float p_o102650_k = 0.007200000;
const float p_o102652_x = 0.000000000;
const float p_o102652_y = 0.000000000;
const float p_o102652_z = -0.243500000;
const float p_o102671_k = 0.000000000;
const float p_o102672_r = 0.017100000;
const float p_o102758_d = 0.000000000;
const float p_o102759_ax = -0.159016000;
const float p_o102759_ay = -0.344262000;
const float p_o102759_bx = 0.155738000;
const float p_o102759_by = -0.183607000;
const float p_o102759_cx = 0.142623000;
const float p_o102759_cy = 0.006557000;
const float p_o102759_r = 0.006000000;
const float p_o102649_r = 0.070400000;
const float p_o102648_d = 0.000000000;
const float p_o102767_x = 0.000000000;
const float p_o102767_y = -0.036700000;
const float p_o102755_ax = 0.058000000;
const float p_o102755_ay = -0.090000000;
const float p_o102755_bx = 0.118289000;
const float p_o102755_by = 0.190000000;
const float p_o102755_cx = 0.253780000;
const float p_o102755_cy = 0.141000000;
const float p_o102755_r = 0.008000000;
const float p_o102757_ax = -0.091000000;
const float p_o102757_ay = -0.227000000;
const float p_o102757_bx = 0.026000000;
const float p_o102757_by = -0.235000000;
const float p_o102757_cx = 0.058000000;
const float p_o102757_cy = -0.090000000;
const float p_o102757_r = 0.008000000;
const float p_o102669_in_min = 0.015600000;
const float p_o102669_in_max = 0.158200000;
const float p_o102669_out_min = 0.466700000;
const float p_o102669_out_max = 1.159700000;
const float p_o102653_curve_0_x = 0.000000000;
const float p_o102653_curve_0_y = 0.000000000;
const float p_o102653_curve_0_ls = 0.000000000;
const float p_o102653_curve_0_rs = 1.000000000;
const float p_o102653_curve_1_x = 1.000000000;
const float p_o102653_curve_1_y = 1.000000000;
const float p_o102653_curve_1_ls = 1.000000000;
const float p_o102653_curve_1_rs = 0.000000000;
float o102653_curve_curve_fct(float x) {
{
float dx = x - p_o102653_curve_0_x;
float d = p_o102653_curve_1_x - p_o102653_curve_0_x;
float t = dx/d;
float omt = (1.0 - t);
float omt2 = omt * omt;
float omt3 = omt2 * omt;
float t2 = t * t;
float t3 = t2 * t;
d /= 3.0;
float y1 = p_o102653_curve_0_y;
float yac = p_o102653_curve_0_y + d*p_o102653_curve_0_rs;
float ybc = p_o102653_curve_1_y - d*p_o102653_curve_1_ls;
float y2 = p_o102653_curve_1_y;
return y1*omt3 + yac*omt2*t*3.0 + ybc*omt*t2*3.0 + y2*t3;
}
}
vec2 o102630_input_distance(vec3 p, float _seed_variation_) {
vec2 o102631_0_q = vec2(length((((rotate3d((p), -vec3(p_o102763_ax, p_o102763_ay, p_o102763_az)*0.01745329251)))/p_o102766_s).xy)-p_o102631_d+0.5, (((rotate3d((p), -vec3(p_o102763_ax, p_o102763_ay, p_o102763_az)*0.01745329251)))/p_o102766_s).z+0.5);
float o102753_0_1_sdf2d = sdBezier((o102631_0_q),vec2(p_o102753_ax,p_o102753_ay)+0.5,vec2(p_o102753_bx,p_o102753_by)+0.5,vec2(p_o102753_cx,p_o102753_cy)+0.5)-p_o102753_r*1.0;
float o102631_0_1_sdf3d = o102753_0_1_sdf2d;
float o102632_0_1_sdf3d = sdCylinder(((((rotate3d((p), -vec3(p_o102763_ax, p_o102763_ay, p_o102763_az)*0.01745329251)))/p_o102766_s)-vec3(p_o102633_x, p_o102633_y, p_o102633_z)).xzy, p_o102632_l, p_o102632_r);
vec2 o102633_0_1_sdf3dc = vec2(o102632_0_1_sdf3d, 0.0);
vec2 o102634_0_v = o102633_0_1_sdf3dc;vec2 o102634_0_1_sdf3dc = vec2(o102634_0_v.x-p_o102634_r, o102634_0_v.y);
vec2 o102635_0_1_sdf3dc = sdf3d_smooth_union(vec2(o102631_0_1_sdf3d, 0.0), o102634_0_1_sdf3dc, p_o102635_k);
vec2 o102637_0_q = vec2(length((((rotate3d((p), -vec3(p_o102763_ax, p_o102763_ay, p_o102763_az)*0.01745329251)))/p_o102766_s).xy)-p_o102637_d+0.5, (((rotate3d((p), -vec3(p_o102763_ax, p_o102763_ay, p_o102763_az)*0.01745329251)))/p_o102766_s).z+0.5);
float o102754_0_1_sdf2d = sdBezier((o102637_0_q),vec2(p_o102754_ax,p_o102754_ay)+0.5,vec2(p_o102754_bx,p_o102754_by)+0.5,vec2(p_o102754_cx,p_o102754_cy)+0.5)-p_o102754_r*1.0;
float o102637_0_1_sdf3d = o102754_0_1_sdf2d;
vec2 o102636_0_1_sdf3dc = sdf3dc_union(o102635_0_1_sdf3dc, vec2(o102637_0_1_sdf3d, 0.0));
float o102638_0_1_sdf3d = length(((((((rotate3d((p), -vec3(p_o102763_ax, p_o102763_ay, p_o102763_az)*0.01745329251)))/p_o102766_s)-vec3(p_o102640_x, p_o102640_y, p_o102640_z)))/vec3(p_o102639_sx*p_o102639_s,p_o102639_sy*p_o102639_s,p_o102639_sz*p_o102639_s)))-p_o102638_r;
vec2 o102639_0_in = vec2(o102638_0_1_sdf3d, 0.0);vec2 o102639_0_1_sdf3dc = vec2(o102639_0_in.x*min(min(p_o102639_sx*p_o102639_s,p_o102639_sy*p_o102639_s),p_o102639_sz*p_o102639_s), o102639_0_in.y);
vec2 o102640_0_1_sdf3dc = o102639_0_1_sdf3dc;
vec2 o102641_0_1_sdf3dc = sdf3d_smooth_union(o102636_0_1_sdf3dc, o102640_0_1_sdf3dc, p_o102641_k);
float o102760_0_1_sdf2d = sdBezier((((((rotate3d((p), -vec3(p_o102763_ax, p_o102763_ay, p_o102763_az)*0.01745329251)))/p_o102766_s)-vec3(p_o102644_x, p_o102644_y, p_o102644_z)).xz+vec2(0.5)),vec2(p_o102760_ax,p_o102760_ay)+0.5,vec2(p_o102760_bx,p_o102760_by)+0.5,vec2(p_o102760_cx,p_o102760_cy)+0.5)-p_o102760_r*1.0;
float o102762_0_1_sdf2d = sdBezier((((((rotate3d((p), -vec3(p_o102763_ax, p_o102763_ay, p_o102763_az)*0.01745329251)))/p_o102766_s)-vec3(p_o102644_x, p_o102644_y, p_o102644_z)).xz+vec2(0.5)),vec2(p_o102762_ax,p_o102762_ay)+0.5,vec2(p_o102762_bx,p_o102762_by)+0.5,vec2(p_o102762_cx,p_o102762_cy)+0.5)-p_o102762_r*1.0;
float o102761_0_1_sdf2d = min( o102760_0_1_sdf2d, o102762_0_1_sdf2d);
vec2 o102642_0_w = vec2(o102761_0_1_sdf2d,abs(((((rotate3d((p), -vec3(p_o102763_ax, p_o102763_ay, p_o102763_az)*0.01745329251)))/p_o102766_s)-vec3(p_o102644_x, p_o102644_y, p_o102644_z)).y)-p_o102642_d);
float o102642_0_1_sdf3d = min(max(o102642_0_w.x,o102642_0_w.y),0.0)+length(max(o102642_0_w,0.0));
vec2 o102645_0_v = vec2(o102642_0_1_sdf3d, 0.0);vec2 o102645_0_1_sdf3dc = vec2(o102645_0_v.x-p_o102645_r, o102645_0_v.y);
vec2 o102644_0_1_sdf3dc = o102645_0_1_sdf3dc;
vec2 o102643_0_1_sdf3dc = sdf3d_smooth_union(o102641_0_1_sdf3dc, o102644_0_1_sdf3dc, p_o102643_k);
float o102651_0_1_sdf3d = ((((((rotate3d((p), -vec3(p_o102763_ax, p_o102763_ay, p_o102763_az)*0.01745329251)))/p_o102766_s)-vec3(p_o102647_x, p_o102647_y, p_o102647_z))-clamp(((((rotate3d((p), -vec3(p_o102763_ax, p_o102763_ay, p_o102763_az)*0.01745329251)))/p_o102766_s)-vec3(p_o102647_x, p_o102647_y, p_o102647_z)), -abs(vec3(p_o102670_x, p_o102670_y, p_o102670_z)), abs(vec3(p_o102670_x, p_o102670_y, p_o102670_z))))-vec3(p_o102652_x, p_o102652_y, p_o102652_z)).z;
vec2 o102652_0_1_sdf3dc = vec2(o102651_0_1_sdf3d, 0.0);
float o102759_0_1_sdf2d = sdBezier(((((((rotate3d((p), -vec3(p_o102763_ax, p_o102763_ay, p_o102763_az)*0.01745329251)))/p_o102766_s)-vec3(p_o102647_x, p_o102647_y, p_o102647_z))-clamp(((((rotate3d((p), -vec3(p_o102763_ax, p_o102763_ay, p_o102763_az)*0.01745329251)))/p_o102766_s)-vec3(p_o102647_x, p_o102647_y, p_o102647_z)), -abs(vec3(p_o102670_x, p_o102670_y, p_o102670_z)), abs(vec3(p_o102670_x, p_o102670_y, p_o102670_z)))).xz+vec2(0.5)),vec2(p_o102759_ax,p_o102759_ay)+0.5,vec2(p_o102759_bx,p_o102759_by)+0.5,vec2(p_o102759_cx,p_o102759_cy)+0.5)-p_o102759_r*1.0;
vec2 o102758_0_w = vec2(o102759_0_1_sdf2d,abs((((((rotate3d((p), -vec3(p_o102763_ax, p_o102763_ay, p_o102763_az)*0.01745329251)))/p_o102766_s)-vec3(p_o102647_x, p_o102647_y, p_o102647_z))-clamp(((((rotate3d((p), -vec3(p_o102763_ax, p_o102763_ay, p_o102763_az)*0.01745329251)))/p_o102766_s)-vec3(p_o102647_x, p_o102647_y, p_o102647_z)), -abs(vec3(p_o102670_x, p_o102670_y, p_o102670_z)), abs(vec3(p_o102670_x, p_o102670_y, p_o102670_z)))).y)-p_o102758_d);
float o102758_0_1_sdf3d = min(max(o102758_0_w.x,o102758_0_w.y),0.0)+length(max(o102758_0_w,0.0));
vec2 o102672_0_v = vec2(o102758_0_1_sdf3d, 0.0);vec2 o102672_0_1_sdf3dc = vec2(o102672_0_v.x-p_o102672_r, o102672_0_v.y);
float o102755_0_1_sdf2d = sdBezier((((((((rotate3d((p), -vec3(p_o102763_ax, p_o102763_ay, p_o102763_az)*0.01745329251)))/p_o102766_s)-vec3(p_o102647_x, p_o102647_y, p_o102647_z))-clamp(((((rotate3d((p), -vec3(p_o102763_ax, p_o102763_ay, p_o102763_az)*0.01745329251)))/p_o102766_s)-vec3(p_o102647_x, p_o102647_y, p_o102647_z)), -abs(vec3(p_o102670_x, p_o102670_y, p_o102670_z)), abs(vec3(p_o102670_x, p_o102670_y, p_o102670_z)))).xz+vec2(0.5))-vec2(p_o102767_x, p_o102767_y)),vec2(p_o102755_ax,p_o102755_ay)+0.5,vec2(p_o102755_bx,p_o102755_by)+0.5,vec2(p_o102755_cx,p_o102755_cy)+0.5)-p_o102755_r*1.0;
float o102757_0_1_sdf2d = sdBezier((((((((rotate3d((p), -vec3(p_o102763_ax, p_o102763_ay, p_o102763_az)*0.01745329251)))/p_o102766_s)-vec3(p_o102647_x, p_o102647_y, p_o102647_z))-clamp(((((rotate3d((p), -vec3(p_o102763_ax, p_o102763_ay, p_o102763_az)*0.01745329251)))/p_o102766_s)-vec3(p_o102647_x, p_o102647_y, p_o102647_z)), -abs(vec3(p_o102670_x, p_o102670_y, p_o102670_z)), abs(vec3(p_o102670_x, p_o102670_y, p_o102670_z)))).xz+vec2(0.5))-vec2(p_o102767_x, p_o102767_y)),vec2(p_o102757_ax,p_o102757_ay)+0.5,vec2(p_o102757_bx,p_o102757_by)+0.5,vec2(p_o102757_cx,p_o102757_cy)+0.5)-p_o102757_r*1.0;
float o102756_0_1_sdf2d = min( o102755_0_1_sdf2d, o102757_0_1_sdf2d);
float o102767_0_1_sdf2d = o102756_0_1_sdf2d;
vec2 o102648_0_w = vec2(o102767_0_1_sdf2d,abs((((((rotate3d((p), -vec3(p_o102763_ax, p_o102763_ay, p_o102763_az)*0.01745329251)))/p_o102766_s)-vec3(p_o102647_x, p_o102647_y, p_o102647_z))-clamp(((((rotate3d((p), -vec3(p_o102763_ax, p_o102763_ay, p_o102763_az)*0.01745329251)))/p_o102766_s)-vec3(p_o102647_x, p_o102647_y, p_o102647_z)), -abs(vec3(p_o102670_x, p_o102670_y, p_o102670_z)), abs(vec3(p_o102670_x, p_o102670_y, p_o102670_z)))).y)-p_o102648_d);
float o102648_0_1_sdf3d = min(max(o102648_0_w.x,o102648_0_w.y),0.0)+length(max(o102648_0_w,0.0));
vec2 o102649_0_v = vec2(o102648_0_1_sdf3d, 0.0);float o102653_0_1_f = o102653_curve_curve_fct(((((((rotate3d((p), -vec3(p_o102763_ax, p_o102763_ay, p_o102763_az)*0.01745329251)))/p_o102766_s)-vec3(p_o102647_x, p_o102647_y, p_o102647_z))-clamp(((((rotate3d((p), -vec3(p_o102763_ax, p_o102763_ay, p_o102763_az)*0.01745329251)))/p_o102766_s)-vec3(p_o102647_x, p_o102647_y, p_o102647_z)), -abs(vec3(p_o102670_x, p_o102670_y, p_o102670_z)), abs(vec3(p_o102670_x, p_o102670_y, p_o102670_z))))).x);
vec4 o102669_0_1_rgba = vec4(vec3(p_o102669_out_min)+(vec4(vec3(o102653_0_1_f), 1.0).rgb-vec3(p_o102669_in_min))*vec3((p_o102669_out_max-(p_o102669_out_min))/(p_o102669_in_max-(p_o102669_in_min))), vec4(vec3(o102653_0_1_f), 1.0).a);
vec2 o102649_0_1_sdf3dc = vec2(o102649_0_v.x-p_o102649_r*(dot((o102669_0_1_rgba).rgb, vec3(1.0))/3.0), o102649_0_v.y);
vec2 o102671_0_1_sdf3dc = sdf3d_smooth_subtraction(o102672_0_1_sdf3dc, o102649_0_1_sdf3dc, p_o102671_k);
vec2 o102650_0_1_sdf3dc = sdf3d_smooth_subtraction(o102652_0_1_sdf3dc, o102671_0_1_sdf3dc, p_o102650_k);
vec2 o102670_0_1_sdf3dc = o102650_0_1_sdf3dc;
vec2 o102647_0_1_sdf3dc = o102670_0_1_sdf3dc;
vec2 o102646_0_1_sdf3dc = sdf3d_smooth_union(o102643_0_1_sdf3dc, o102647_0_1_sdf3dc, p_o102646_k);
vec2 o102766_0_in = o102646_0_1_sdf3dc;vec2 o102766_0_1_sdf3dc = vec2(o102766_0_in.x*p_o102766_s, o102766_0_in.y);
vec2 o102763_0_1_sdf3dc = o102766_0_1_sdf3dc;
return o102763_0_1_sdf3dc;
}
const float p_o102764_ax = 35.000000000;
const float p_o102764_ay = 180.000000000;
const float p_o102764_az = 215.000000000;
const float p_o102692_amount = 1.000000000;
const float p_o102693_color = 1.000000000;
const float p_o102768_cx = 0.000000000;
const float p_o102768_cy = 0.000000000;
const float p_o102768_scale_x = 1.400000000;
const float p_o102768_scale_y = 1.400000000;
const float p_o102676_g_0_pos = 0.000000000;
const vec4 p_o102676_g_0_col = vec4(1.000000000, 1.000000000, 1.000000000, 1.000000000);
const float p_o102676_g_1_pos = 0.532577000;
const vec4 p_o102676_g_1_col = vec4(0.000000000, 0.000000000, 0.000000000, 1.000000000);
vec4 o102676_g_gradient_fct(float x) {
  if (x < 0.5*(p_o102676_g_0_pos+p_o102676_g_1_pos)) {
    return p_o102676_g_0_col;
  }
  return p_o102676_g_1_col;
}
const float p_o102752_color = 0.000000000;
vec2 GetDist(vec3 p) {
	float _seed_variation_ = seed_variation;

	if (false) {
		p *= vec3(1.0, -1.0, 1.0);
	}


	vec2 d = o102630_input_distance(p, _seed_variation_);

	return d;
}
vec2 RayMarch(vec3 ro, vec3 rd) {
	float dO = 0.0;
	float color = 0.0;
	vec2 dS;
	
	for (int i = 0; i < MAX_STEPS; i++) {
		vec3 p = ro + dO * rd;
		dS = GetDist(p);
		dO += dS.x;
		
		if (dS.x < SURF_DIST || dO > MAX_DIST) {
			color = dS.y;
			break;
		}
	}
	return vec2(dO, color);
}
vec3 GetNormal(vec3 p) {
	vec2 e = vec2(1e-2, 0);
	
	vec3 n = GetDist(p).x - vec3(
		GetDist(p - e.xyy).x,
		GetDist(p - e.yxy).x,
		GetDist(p - e.yyx).x
	);
	
	return normalize(n);
}
void vertex() {
	elapsed_time = TIME;
	world_position = VERTEX;
	world_camera = (inverse(MODELVIEW_MATRIX) * vec4(0, 0, 0, 1)).xyz; //object space
//	world_camera = ( CAMERA_MATRIX  * vec4(0, 0, 0, 1)).xyz; //uncomment this to raymarch in world space
}
void fragment() {
	float _seed_variation_ = seed_variation;
	vec3 ro = world_camera;
	vec3 rd =  normalize(world_position - ro);
	
	vec2 rm  = RayMarch(ro, rd);
	float d = rm.x;
	if (d >= MAX_DIST) {
		discard;
	} else {
		vec3 p = ro + rd * d;
		vec3 n = GetNormal(p);

		if (false) {
			p *= vec3(1.0, -1.0, 1.0);
			n *= vec3(1.0, -1.0, 1.0);
		} 

float o102693_0_1_tex3d_gs = p_o102693_color;
//vec4 o102704_0 = textureLod(o102704_tex, scale(((vec4(tex3d_rotate((vec4(p, rm.y)).xyz, -vec3(p_o102764_ax, p_o102764_ay, p_o102764_az)*0.01745329251), (vec4(p, rm.y)).w)).xy+vec2(0.5)), vec2(0.5+p_o102768_cx, 0.5+p_o102768_cy), vec2(p_o102768_scale_x, p_o102768_scale_y)), 0.0);
//vec4 o102768_0_1_rgba = o102704_0;
//vec3 o102673_0_1_tex3d = ((o102768_0_1_rgba).rgb);
float o102675_0_1_tex3d_gs = ((vec4(tex3d_rotate((vec4(p, rm.y)).xyz, -vec3(p_o102764_ax, p_o102764_ay, p_o102764_az)*0.01745329251), (vec4(p, rm.y)).w)).z);
vec3 o102676_0_1_tex3d = o102676_g_gradient_fct(dot(vec3(o102675_0_1_tex3d_gs), vec3(1.0))/3.0).rgb;
//vec3 o102692_0_1_tex3d = blend3d_normal(vec3(o102693_0_1_tex3d_gs).rgb, o102673_0_1_tex3d.rgb, p_o102692_amount*dot(o102676_0_1_tex3d, vec3(1.0))/3.0);
//vec3 o102764_0_1_tex3d = o102692_0_1_tex3d;
float o102752_0_1_tex3d_gs = p_o102752_color;

//		ALBEDO = o102764_0_1_tex3d;
//		ROUGHNESS = o102752_0_1_tex3d_gs;
		METALLIC = 0.0;
		EMISSION = vec3(0.0);

		NORMAL = (INV_VIEW_MATRIX*vec4(n, 0.0)).xyz;
	}
}



